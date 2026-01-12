`include "cpu.vh"

module exe_stage(
    input clk, reset,

    // 握手信号
    output exe_allow_in,
    input id_to_exe_valid,
    input mem_allow_in,
    output exe_to_mem_valid,

    input [`ID_TO_EXE_BUS_WIDTH-1:0] id_to_exe_bus,
    output [`EXE_TO_MEM_BUS_WIDTH-1:0] exe_to_mem_bus,

    // 冲突检测
    output [`EXE_TO_ID_BUS_WIDTH-1:0] exe_to_id_bus,

    // CPU 数据存储器简单接口（由 mycpu_top 适配为类SRAM握手）
    output          data_sram_en,
    output[3:0]     data_sram_wen,
    output[31:0]    data_sram_addr,
    output[31:0]    data_sram_wdata,
    output[1:0]     data_sram_size
);
    // id to exe bus
    reg [`ID_TO_EXE_BUS_WIDTH-1:0] exe_reg;
    wire[31:0] pc;
    wire[22:0] inst_decode;
    wire[31:0] imm; 
    wire[31:0] rk_val; 
    wire[31:0] rj_val;
    wire[31:0] rd_val;
    wire[4:0] rd;
    wire[3:0] exe_alu_op;
    assign {
        pc, 
        inst_decode, 
        imm, 
        rk_val, 
        rj_val, 
        rd_val, 
        rd, 
        exe_alu_op
    } = exe_reg;

    // exe to mem bus
    wire [31:0] exe_alu_output;
    
    // logic for correct rd (handling BL writing to r1)
    wire [4:0] exe_rd;
    assign exe_rd = (inst_decode[`IDX_BL]) ? 5'd1 : rd;

    assign exe_to_mem_bus = {
        pc,
        inst_decode,
        exe_alu_output,
        exe_rd
    };

    // ALU
    wire [31:0] op1;
    wire [31:0] op2;
    wire [`ALU_OP_WIDTH-1:0] alu_op;
    wire [31:0] alu_output;

    alu_ ualu(
        .op1(op1),
        .op2(op2),
        .alu_op(alu_op),
        .alu_output(alu_output)
    );

    // op1 selection
    assign op1 = (inst_decode[`IDX_JIRL] || inst_decode[`IDX_BL] || inst_decode[`IDX_PCADDU12I]) ? pc : rj_val; // For JIRL/BL/PCADDU12I, op1 is PC.

    // op2 selection
    // Instructions using rk_val as source 2: ADD, SUB, AND, OR, XOR, MUL.
    // Others use imm (or constant 4 for link).
    assign op2 = (inst_decode[`IDX_ADD_W] || inst_decode[`IDX_SUB_W] || 
                  inst_decode[`IDX_AND]   || inst_decode[`IDX_MUL_W] || 
                  inst_decode[`IDX_OR]    || inst_decode[`IDX_XOR]) ? rk_val : 
                 (inst_decode[`IDX_JIRL]  || inst_decode[`IDX_BL]) ? 32'd4 : // For Link instructions, result is PC+4
                 imm;

    assign alu_op = exe_alu_op;
    assign exe_alu_output = alu_output;

    // exe_to_id_bus
    wire exe_write;
    wire [31:0] exe_wdata;
    
    // Instructions that write to RF:
    // ALU ops, Loads, LUI, PCADDU12I, JIRL, BL.
         
    assign exe_write = exe_valid && (exe_rd != 0) && 
        (inst_decode[`IDX_ADD_W] || inst_decode[`IDX_SUB_W] || inst_decode[`IDX_AND] || inst_decode[`IDX_MUL_W] || 
         inst_decode[`IDX_SLLI_W] || inst_decode[`IDX_SLTI] || inst_decode[`IDX_ADDI_W] || inst_decode[`IDX_ORI] || 
         inst_decode[`IDX_LD_W] || inst_decode[`IDX_LD_B] || 
         inst_decode[`IDX_LU12I_W] || inst_decode[`IDX_PCADDU12I] || 
         inst_decode[`IDX_OR] || inst_decode[`IDX_ANDI] || inst_decode[`IDX_XOR] || inst_decode[`IDX_SRLI_W] || 
         inst_decode[`IDX_JIRL] || inst_decode[`IDX_BL]); // BL/JIRL write link address
         
    assign exe_wdata = exe_alu_output;
    wire exe_is_load = inst_decode[`IDX_LD_W] | inst_decode[`IDX_LD_B];
    assign exe_to_id_bus = {exe_rd, exe_write, exe_is_load, exe_wdata};

    // 流水线握手
    reg  exe_valid;
    wire exe_ready_go;

    assign exe_ready_go = 1;
    assign exe_allow_in = !exe_valid || (exe_ready_go && mem_allow_in);
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

    // 数据存储器简单接口：当指令为 load/store 且 exe_valid 为 1 时，启用 data_sram。
    assign data_sram_en    = (inst_decode[`IDX_LD_W] || inst_decode[`IDX_LD_B] || inst_decode[`IDX_ST_W] || inst_decode[`IDX_ST_B]) && exe_valid;
    assign data_sram_wen   = 
        inst_decode[`IDX_ST_W] ? 4'b1111 : 
        inst_decode[`IDX_ST_B] ? (4'b0001 << exe_alu_output[1:0]) : 
        4'b0000;
    assign data_sram_addr  = exe_alu_output;
    assign data_sram_wdata = inst_decode[`IDX_ST_B] ? {4{rd_val[7:0]}} : rd_val;
    assign data_sram_size  = (inst_decode[`IDX_LD_B] || inst_decode[`IDX_ST_B]) ? 2'b00 : 2'b10;

endmodule
