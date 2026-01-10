`include "mycpu_top.h"

module mem_stage (
    input clk,
    input reset,

    // pipeline control
    output mem_allow_in,
    input  exe_to_mem_valid,
    input  wb_allow_in,
    output mem_to_wb_valid,

    // bus from exe
    input [`EXE_TO_MEM_BUS_WIDTH-1:0] exe_to_mem_bus,

    // bus to wb
    output [`MEM_TO_WB_BUS_WIDTH-1:0] mem_to_wb_bus,

    // bus to id (for hazard detect)
    output [`MEM_TO_ID_BUS_WIDTH-1:0] mem_to_id_bus,

    // cpu interface
    input         data_sram_data_ok, // 增加握手信号
    input  [31:0] data_sram_rdata
);

    // pipeline registers
    reg [`EXE_TO_MEM_BUS_WIDTH-1:0] mem_reg;

    wire [31:0] mem_pc;
    wire [31:0] mem_rkd_value;
    wire [31:0] mem_alu_result;
    wire        mem_res_from_mem;
    wire        mem_reg_we;
    wire        mem_mem_en;
    wire [3:0]  mem_mem_we;
    wire [4:0]  mem_reg_waddr;

    assign {mem_pc, 
            mem_rkd_value, 
            mem_alu_result, 
            mem_res_from_mem, 
            mem_reg_we, 
            mem_mem_en,
            mem_mem_we, 
            mem_reg_waddr
        } = mem_reg;

    // ------------------------------------------------------------------
    // MEM Stage Data Buffer (解决数据来了但WB堵住的情况)
    // ------------------------------------------------------------------
    reg        mem_data_buf_valid; // Buffer 里是否有有效数据
    reg [31:0] mem_data_buf;       // 缓存的数据

    // Buffer 控制逻辑
    always @(posedge clk) begin
        if (reset) begin
            mem_data_buf_valid <= 1'b0;
            mem_data_buf       <= 32'b0;
        end else if (mem_mem_en && data_sram_data_ok && !wb_allow_in && !mem_data_buf_valid) begin
            // 场景：是访存指令 AND 数据回来了 AND WB不收 AND Buffer为空
            // 动作：抓取数据存入 Buffer
            mem_data_buf_valid <= 1'b1;
            mem_data_buf       <= data_sram_rdata;
        end else if (wb_allow_in && mem_ready_go) begin
            // 场景：数据流向了 WB
            // 动作：Buffer 失效
            mem_data_buf_valid <= 1'b0;
        end
    end

    // output bus to WB
    wire [31:0] final_result;
    assign mem_to_wb_bus = {mem_pc,        // 32 bits
                           final_result,  // 32 bits
                           mem_reg_we,    // 1 bit
                           mem_reg_waddr  // 5 bits
                           };

    assign mem_to_id_bus = {mem_valid, mem_reg_we, mem_reg_waddr, final_result};

    // pipeline control
    reg  mem_valid;
    wire mem_ready_go;

    // 1. 如果不是访存指令 (!mem_mem_en)，直接 Ready。
    // 2. 如果是访存指令，需要等待 data_ok 到来，或者数据已经在 Buffer 里了。
    assign mem_ready_go = !mem_mem_en || data_sram_data_ok || mem_data_buf_valid;

    assign mem_allow_in = !mem_valid || mem_ready_go && wb_allow_in;
    assign mem_to_wb_valid = mem_valid && mem_ready_go;
    always @(posedge clk) begin
        if (reset) begin
            mem_valid <= 1'b0;
        end else if (mem_allow_in) begin
            mem_valid <= exe_to_mem_valid;
        end
    end

    always @(posedge clk) begin
        if (mem_allow_in && exe_to_mem_valid) begin
            mem_reg <= exe_to_mem_bus;
        end
    end

    // internal signals
    wire [31:0] mem_result;

    // MEM stage
    // 如果 Buffer 有效，从 Buffer 拿；否则从 SRAM 接口拿
    assign mem_result   = mem_data_buf_valid ? mem_data_buf : data_sram_rdata;

    assign final_result = mem_res_from_mem ? mem_result : mem_alu_result;


endmodule