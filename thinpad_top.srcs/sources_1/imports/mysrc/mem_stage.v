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
    input         data_sram_data_ok, 
    input  [31:0] data_sram_rdata
);

    reg [`EXE_TO_MEM_BUS_WIDTH-1:0] mem_reg;

    wire [31:0] mem_pc;
    wire [31:0] mem_rkd_value;
    wire [31:0] mem_alu_result;
    wire        mem_res_from_mem; // 这是一个标记是否为 Load 的信号
    wire        mem_reg_we;
    wire        mem_mem_en;
    wire [3:0]  mem_mem_we;
    wire [4:0]  mem_reg_waddr;
    wire [1:0]  mem_sram_size; 

    assign {mem_pc, 
            mem_rkd_value, 
            mem_alu_result, 
            mem_res_from_mem, 
            mem_reg_we, 
            mem_mem_en,
            mem_mem_we, 
            mem_reg_waddr,
            mem_sram_size
        } = mem_reg;

    // Buffer Logic
    reg        mem_data_buf_valid; 
    reg [31:0] mem_data_buf;       

    always @(posedge clk) begin
        if (reset) begin
            mem_data_buf_valid <= 1'b0;
            mem_data_buf       <= 32'b0;
        end else if (mem_mem_en && data_sram_data_ok && !wb_allow_in && !mem_data_buf_valid) begin
            mem_data_buf_valid <= 1'b1;
            mem_data_buf       <= data_sram_rdata;
        end else if (wb_allow_in && mem_ready_go) begin
            mem_data_buf_valid <= 1'b0;
        end
    end

    // Load Byte Post-Processing
    wire [31:0] mem_result_raw;
    assign mem_result_raw = mem_data_buf_valid ? mem_data_buf : data_sram_rdata;

    wire [1:0] addr_low = mem_alu_result[1:0];
    wire [7:0] byte_val = (addr_low == 2'b00) ? mem_result_raw[7:0] :
                          (addr_low == 2'b01) ? mem_result_raw[15:8] :
                          (addr_low == 2'b10) ? mem_result_raw[23:16] :
                                                mem_result_raw[31:24];
    wire [31:0] mem_result_final;
    assign mem_result_final = (mem_sram_size == 2'b00) ? {{24{byte_val[7]}}, byte_val} : mem_result_raw;

    // Result Mux
    wire [31:0] final_result;
    assign final_result = mem_res_from_mem ? mem_result_final : mem_alu_result;

    // Output Buses
    assign mem_to_wb_bus = {mem_pc,        
                           final_result,  
                           mem_reg_we,    
                           mem_reg_waddr  
                           };
    
    // 修改：将 mem_res_from_mem 加入到反馈给 ID 的总线中
    assign mem_to_id_bus = {mem_valid, mem_reg_we, mem_reg_waddr, final_result, mem_res_from_mem};

    // Control
    reg  mem_valid;
    wire mem_ready_go;
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

endmodule