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
    // output        data_sram_en,
    // output [ 3:0] data_sram_we,
    // output [31:0] data_sram_addr,
    // output [31:0] data_sram_wdata
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

    // output bus to WB
    wire [31:0] final_result;
    assign mem_to_wb_bus = {mem_pc,        // 32 bits
                           final_result,  // 32 bits
                           mem_reg_we,    // 1 bit
                           mem_reg_waddr  // 5 bits
                           };
    // assign mem_to_wb_bus = {mem_pc,        // 32 bits
    //                         mem_alu_result,  // 32 bits
    //                         mem_res_from_mem, // 1 bit
    //                         mem_reg_we,    // 1 bit
    //                         mem_reg_waddr  // 5 bits
    //                         };

    assign mem_to_id_bus = {mem_valid, mem_reg_we, mem_reg_waddr, final_result};

    // pipeline control
    reg  mem_valid;
    wire mem_ready_go;

    assign mem_ready_go = 1;
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
    // assign data_sram_en    = mem_valid && mem_mem_en;
    // assign data_sram_we    = mem_mem_we;
    // assign data_sram_addr  = data_sram_en ? mem_alu_result : 32'b0;
    // assign data_sram_wdata = mem_rkd_value;
    assign mem_result      = data_sram_rdata;
    assign final_result    = mem_res_from_mem ? mem_result : mem_alu_result;


endmodule