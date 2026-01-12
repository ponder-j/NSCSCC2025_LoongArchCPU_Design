`include "mycpu_top.h"

module exe_stage (
    input clk,
    input reset,

    // pipeline control
    output exe_allow_in,
    input  id_to_exe_valid,
    input  mem_allow_in,
    output exe_to_mem_valid,

    // bus from id
    input [`ID_TO_EXE_BUS_WIDTH-1:0] id_to_exe_bus,

    // bus to mem
    output [`EXE_TO_MEM_BUS_WIDTH-1:0] exe_to_mem_bus,

    // bus to id (for hazard detect)
    output [`EXE_TO_ID_BUS_WIDTH-1:0] exe_to_id_bus,

    // data sram interface
    output wire        data_sram_req    ,
    output wire        data_sram_wr     ,
    output wire [ 1:0] data_sram_size   ,
    output wire [ 3:0] data_sram_wstrb  ,
    output wire [31:0] data_sram_addr   ,
    output wire [31:0] data_sram_wdata  ,
    input  wire        data_sram_addr_ok,
    input  wire        data_sram_data_ok,
    input  wire [31:0] data_sram_rdata
);

    reg [`ID_TO_EXE_BUS_WIDTH-1:0] exe_reg;
    wire [31:0] exe_pc;
    wire [31:0] exe_rj_value;
    wire [31:0] exe_rkd_value;
    wire [31:0] exe_imm;
    wire [11:0] exe_alu_op;
    wire        exe_src1_is_pc;
    wire        exe_src2_is_imm;
    wire        exe_res_from_mem;
    wire        exe_reg_we;
    wire        exe_mem_en;
    wire [3:0]  exe_mem_we;
    wire [4:0]  exe_reg_waddr;
    wire [1:0]  exe_sram_size; // New

    assign {
        exe_pc,
        exe_rj_value,
        exe_rkd_value,
        exe_imm,
        exe_alu_op,
        exe_src1_is_pc,
        exe_src2_is_imm,
        exe_res_from_mem,
        exe_reg_we,
        exe_mem_en,
        exe_mem_we,
        exe_reg_waddr,
        exe_sram_size
    } = exe_reg;

    // output bus to MEM
    wire [31:0] alu_result;
    assign exe_to_mem_bus = {
        exe_pc,           
        exe_rkd_value,    
        alu_result,       
        exe_res_from_mem, 
        exe_reg_we,       
        exe_mem_en,       
        exe_mem_we,       
        exe_reg_waddr,
        exe_sram_size 
    };

    assign exe_to_id_bus = {exe_valid, exe_reg_we, exe_reg_waddr, alu_result, exe_res_from_mem};

    // SRAM Request Logic
    reg data_sram_req_done; 
    always @(posedge clk) begin
        if (reset) begin
            data_sram_req_done <= 1'b0;
        end else if (exe_ready_go && mem_allow_in) begin
            data_sram_req_done <= 1'b0;
        end else if (data_sram_req && data_sram_addr_ok) begin
            data_sram_req_done <= 1'b1;
        end
    end

    assign data_sram_req = exe_valid && exe_mem_en && !data_sram_req_done;
    assign data_sram_wr    = |exe_mem_we;
    assign data_sram_size  = exe_sram_size;
    assign data_sram_addr  = alu_result;
    
    // Store Byte Logic
    // If it's a byte store (size==00), we need to set the correct strobe bit
    // based on address [1:0] and shift the data.
    wire [1:0] addr_low = alu_result[1:0];
    wire [31:0] sb_data = {4{exe_rkd_value[7:0]}}; // Broadcast byte
    
    assign data_sram_wdata = (exe_sram_size == 2'b00) ? sb_data : exe_rkd_value;

    assign data_sram_wstrb = (exe_sram_size == 2'b00) ? (
                                (addr_low == 2'b00) ? 4'b0001 :
                                (addr_low == 2'b01) ? 4'b0010 :
                                (addr_low == 2'b10) ? 4'b0100 : 4'b1000
                             ) : exe_mem_we; 

    // Pipeline Control
    reg  exe_valid;
    wire exe_ready_go;
    assign exe_ready_go = !exe_mem_en || (data_sram_req && data_sram_addr_ok) || data_sram_req_done;
    assign exe_allow_in = !exe_valid || exe_ready_go && mem_allow_in;
    assign exe_to_mem_valid = exe_valid && exe_ready_go;

    always @(posedge clk) begin
        if (reset) begin
            exe_valid <= 1'b0;
        end else if (exe_allow_in) begin
            exe_valid <= id_to_exe_valid;
        end
    end

    always @(posedge clk) begin
        if (exe_allow_in && id_to_exe_valid) begin
            exe_reg <= id_to_exe_bus;
        end
    end

    // ALU
    wire [11:0] alu_op = exe_alu_op; 
    wire [31:0] alu_src1 = exe_src1_is_pc ? exe_pc : exe_rj_value;
    wire [31:0] alu_src2 = exe_src2_is_imm ? exe_imm : exe_rkd_value;

    myalu u_alu (
        .alu_op    (alu_op),
        .alu_src1  (alu_src1),
        .alu_src2  (alu_src2),
        .alu_result(alu_result)
    );

endmodule