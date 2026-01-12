`include "cpu.vh"

module id_stage(
    input clk, reset,

    // 握手信号
    output id_allow_in,
    input if_to_id_valid,
    input exe_allow_in,
    output id_to_exe_valid,

    // IF 到 ID 总线
    input  [`IF_TO_ID_BUS_WIDTH-1:0] if_to_id_bus,
    output [`ID_TO_EXE_BUS_WIDTH-1:0] id_to_exe_bus,

    output [`ID_TO_IF_BUS_WIDTH-1:0] id_to_if_bus,

    input  [`WB_TO_ID_BUS_WIDTH-1:0] wb_to_id_bus,

    input [`EXE_TO_ID_BUS_WIDTH-1:0] exe_to_id_bus,

    input [`MEM_TO_ID_BUS_WIDTH-1:0] mem_to_id_bus
);

    reg [`IF_TO_ID_BUS_WIDTH-1:0] id_reg;
    wire [31:0] pc;
    wire [31:0] inst;
    wire [31:0] pred_next_pc;
    wire        pred_br_taken;
    assign {pred_br_taken, pred_next_pc, pc, inst} = id_reg;

    wire[22:0] inst_decode;
    wire[31:0] imm;
    wire[31:0] rk_val;
    wire[31:0] rj_val;
    wire[31:0] rd_val;
    wire[4:0] rd;
    wire[3:0] alu_op;

    assign id_to_exe_bus = {
        pc,
        inst_decode,
        imm,
        rk_val,
        rj_val,
        rd_val,
        rd,
        alu_op
    };

    wire [16:0] opcode_17bit;
    wire [ 9:0] opcode_10bit;
    wire [ 5:0] opcode_6bit;
    wire [ 6:0] opcode_7bit;

    assign opcode_17bit = inst[31:15];
    assign opcode_10bit = inst[31:22];
    assign opcode_6bit  = inst[31:26];
    assign opcode_7bit  = inst[31:25]; // New for lu12i.w/pcaddu12i

    assign inst_decode[`IDX_ADD_W]   = (opcode_17bit == `OP_ADD_W)   ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_SUB_W]   = (opcode_17bit == `OP_SUB_W)   ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_AND]     = (opcode_17bit == `OP_AND)     ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_MUL_W]   = (opcode_17bit == `OP_MUL_W)   ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_SLLI_W]  = (opcode_17bit == `OP_SLLI_W)  ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_SLTI]    = (opcode_10bit == `OP_SLTI)    ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_ADDI_W]  = (opcode_10bit == `OP_ADDI_W)  ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_ORI]     = (opcode_10bit == `OP_ORI)     ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_LD_W]    = (opcode_10bit == `OP_LD_W)    ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_ST_W]    = (opcode_10bit == `OP_ST_W)    ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_B]       = (opcode_6bit  == `OP_B)       ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_BEQ]     = (opcode_6bit  == `OP_BEQ)     ? 1'b1 : 1'b0;
    
    // New instructions decoding
    assign inst_decode[`IDX_LU12I_W]   = (opcode_7bit  == `OP_LU12I_W)   ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_PCADDU12I] = (opcode_7bit  == `OP_PCADDU12I) ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_OR]        = (opcode_17bit == `OP_OR)        ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_ANDI]      = (opcode_10bit == `OP_ANDI)      ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_XOR]       = (opcode_17bit == `OP_XOR)       ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_SRLI_W]    = (opcode_17bit == `OP_SRLI_W)    ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_JIRL]      = (opcode_6bit  == `OP_JIRL)      ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_BNE]       = (opcode_6bit  == `OP_BNE)       ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_BL]        = (opcode_6bit  == `OP_BL)        ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_ST_B]      = (opcode_10bit == `OP_ST_B)      ? 1'b1 : 1'b0;
    assign inst_decode[`IDX_LD_B]      = (opcode_10bit == `OP_LD_B)      ? 1'b1 : 1'b0;

    // LoongArch I26 immediate (B/BL) has scrambled bit order:
    // inst[25:10] = offs[15:0], inst[9:0] = offs[25:16]
    wire [25:0] offs26 = {inst[9:0], inst[25:10]};

    assign imm =
        (inst_decode[`IDX_SLLI_W] | inst_decode[`IDX_SRLI_W]) ? {{27{1'b0}}, inst[14:10]} :
        (inst_decode[`IDX_SLTI] || inst_decode[`IDX_ADDI_W] || inst_decode[`IDX_LD_W] || inst_decode[`IDX_ST_W] || inst_decode[`IDX_LD_B] || inst_decode[`IDX_ST_B]) ? {{20{inst[21]}}, inst[21:10]} :
        (inst_decode[`IDX_ORI] || inst_decode[`IDX_ANDI]) ? {{20{1'b0}}, inst[21:10]} :
        // B/BL: target = PC + SignExtend({offs26, 2'b0}, 32)
        (inst_decode[`IDX_B] || inst_decode[`IDX_BL])   ? {{4{offs26[25]}}, offs26, 2'b0} :
        (inst_decode[`IDX_BEQ] || inst_decode[`IDX_BNE] || inst_decode[`IDX_JIRL]) ? {{14{inst[25]}}, inst[25:10], 2'b0} :
        (inst_decode[`IDX_LU12I_W] || inst_decode[`IDX_PCADDU12I]) ? {inst[24:5], 12'b0} :
        32'b0;

    wire [4:0] rf_raddr1;
    wire [4:0] rf_raddr2;
    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;
    wire rf_we;
    wire [4:0] rf_waddr;
    wire [31:0] rf_wdata;

    regfile u_regfile(
        .clk   (clk),
        .reset (reset),
        .raddr1(rf_raddr1),
        .raddr2(rf_raddr2),
        .rdata1(rf_rdata1),
        .rdata2(rf_rdata2),
        .we    (rf_we),
        .waddr (rf_waddr),
        .wdata (rf_wdata)
    );

    wire [4:0] rk;
    wire [4:0] rj;
    assign rk = inst[14:10];
    assign rj = inst[9:5];
    assign rd = inst[4:0];

    assign rf_raddr1 = rj;
    assign rf_raddr2 = (inst_decode[`IDX_ST_W] || inst_decode[`IDX_ST_B] || inst_decode[`IDX_BEQ] || inst_decode[`IDX_BNE]) ? rd : rk;

    wire read_rf_raddr1;
    wire read_rf_raddr2;
    // Instructions NOT using rj (raddr1): B, BL, LU12I_W, PCADDU12I. 
    // JIRL uses rj.
    assign read_rf_raddr1 = ~(inst_decode[`IDX_B] | inst_decode[`IDX_BL] | inst_decode[`IDX_LU12I_W] | inst_decode[`IDX_PCADDU12I]);
    
    // Instructions using raddr2 (rk or rd): 3R-ALU ops, Stores, Branches (BEQ/BNE).
    assign read_rf_raddr2 = 
        inst_decode[`IDX_ADD_W] | inst_decode[`IDX_SUB_W] | inst_decode[`IDX_AND]   | inst_decode[`IDX_MUL_W] |
        inst_decode[`IDX_OR]    | inst_decode[`IDX_XOR]   | 
        inst_decode[`IDX_ST_W]  | inst_decode[`IDX_ST_B]  | 
        inst_decode[`IDX_BEQ]   | inst_decode[`IDX_BNE];

    wire        raddr1_use;
    wire        raddr2_use;
    wire        exe_forward_valid;
    wire        mem_forward_valid;
    wire        wb_forward_valid;
    wire [31:0] raddr1_val;
    wire [31:0] raddr2_val;

    assign raddr1_use        = (read_rf_raddr1 === 1'b1);
    assign raddr2_use        = (read_rf_raddr2 === 1'b1);

    wire [4:0] exe_rd;
    wire exe_write;
    wire exe_is_load;
    wire [31:0] exe_wdata;
    assign {exe_rd, exe_write, exe_is_load, exe_wdata} = exe_to_id_bus;

    wire [4:0] mem_rd;
    wire mem_write;
    wire [31:0] mem_wdata;
    assign {mem_rd, mem_write, mem_wdata} = mem_to_id_bus;

    wire wb_rf_we;
    wire [4:0] wb_rf_waddr;
    wire [31:0] wb_rf_wdata;
    assign {wb_rf_we, wb_rf_waddr, wb_rf_wdata} = wb_to_id_bus;

    assign exe_forward_valid = exe_write && ~exe_is_load;
    assign mem_forward_valid = mem_write;
    assign wb_forward_valid  = wb_rf_we;

    assign raddr1_val =
        (raddr1_use && exe_forward_valid && (exe_rd == rf_raddr1)) ? exe_wdata :
        (raddr1_use && mem_forward_valid && (mem_rd == rf_raddr1)) ? mem_wdata :
        (raddr1_use && wb_forward_valid  && (wb_rf_waddr == rf_raddr1)) ? wb_rf_wdata :
        rf_rdata1;

    assign raddr2_val =
        (raddr2_use && exe_forward_valid && (exe_rd == rf_raddr2)) ? exe_wdata :
        (raddr2_use && mem_forward_valid && (mem_rd == rf_raddr2)) ? mem_wdata :
        (raddr2_use && wb_forward_valid  && (wb_rf_waddr == rf_raddr2)) ? wb_rf_wdata :
        rf_rdata2;

    assign rj_val = (read_rf_raddr1) ? raddr1_val : 32'h0;
    assign rk_val = (read_rf_raddr2) ? raddr2_val : 32'h0;
    assign rd_val = (inst_decode[`IDX_ST_W] | inst_decode[`IDX_ST_B]) ? raddr2_val : 32'h0; // raddr2 holds rd value for stores

    assign alu_op =
        inst_decode[`IDX_ADD_W]    ? `ALU_ADD :
        inst_decode[`IDX_SUB_W]    ? `ALU_SUB :
        inst_decode[`IDX_AND]      ? `ALU_AND :
        inst_decode[`IDX_MUL_W]    ? `ALU_MUL :
        inst_decode[`IDX_SLLI_W]   ? `ALU_SLL :
        inst_decode[`IDX_SLTI]     ? `ALU_SLT :
        inst_decode[`IDX_ADDI_W]   ? `ALU_ADD :
        inst_decode[`IDX_ORI]      ? `ALU_OR  :
        inst_decode[`IDX_LD_W]     ? `ALU_ADD :
        inst_decode[`IDX_ST_W]     ? `ALU_ADD :
        inst_decode[`IDX_LD_B]     ? `ALU_ADD :
        inst_decode[`IDX_ST_B]     ? `ALU_ADD :
        inst_decode[`IDX_PCADDU12I]? `ALU_ADD : // PC + imm
        inst_decode[`IDX_LU12I_W]  ? `ALU_OP2 : // imm
        inst_decode[`IDX_OR]       ? `ALU_OR  :
        inst_decode[`IDX_ANDI]     ? `ALU_AND :
        inst_decode[`IDX_XOR]      ? `ALU_XOR :
        inst_decode[`IDX_SRLI_W]   ? `ALU_SRL :
        inst_decode[`IDX_JIRL]     ? `ALU_ADD : // Use ALU to calculate PC + 4? No, JIRL writes PC+4 to rd. Target calc is separate. JIRL result (rd) is PC+4.
        inst_decode[`IDX_BL]       ? `ALU_ADD : // BL writes PC+4 to r1.
        `ALU_NOP;

    assign rf_we = wb_rf_we;
    assign rf_waddr = wb_rf_waddr;
    assign rf_wdata = wb_rf_wdata;

    wire        is_branch_inst;
    wire        is_cond_branch;
    wire        actual_br_taken;
    wire [31:0] actual_br_target;
    wire [31:0] seq_pc;
    wire [31:0] actual_next_pc;
    wire        id_fire;
    wire        mispredict;
    wire        upd_en;

    assign is_branch_inst   = inst_decode[`IDX_B] | inst_decode[`IDX_BEQ] | inst_decode[`IDX_JIRL] | inst_decode[`IDX_BNE] | inst_decode[`IDX_BL];
    assign is_cond_branch   = inst_decode[`IDX_BEQ] | inst_decode[`IDX_BNE];
    assign seq_pc           = pc + 32'h4;
    
    // Branch Target Calculation
    // JIRL: rj + imm
    // Others: pc + imm
    assign actual_br_target = (inst_decode[`IDX_JIRL]) ? (rj_val + imm) : (pc + imm);

    assign actual_br_taken  = 
        inst_decode[`IDX_B]    ? 1'b1 :
        inst_decode[`IDX_BL]   ? 1'b1 :
        inst_decode[`IDX_JIRL] ? 1'b1 :
        (inst_decode[`IDX_BEQ] && (rj_val == raddr2_val)) ? 1'b1 :
        (inst_decode[`IDX_BNE] && (rj_val != raddr2_val)) ? 1'b1 :
        1'b0;

    assign actual_next_pc   = actual_br_taken ? actual_br_target : seq_pc;

    reg  id_valid;
    wire id_ready_go;

    assign id_fire     = id_valid && id_ready_go;
    assign mispredict  = id_fire && (pred_next_pc != actual_next_pc);
    assign upd_en      = id_fire;

    assign id_to_if_bus = {
        mispredict,
        actual_next_pc,
        upd_en,
        pc,
        is_branch_inst,
        is_cond_branch,
        actual_br_taken,
        actual_br_target
    };

    wire hazard;
    wire load_hazard_1;
    wire load_hazard_2;

    assign load_hazard_1 = raddr1_use && exe_is_load && exe_write && (exe_rd === rf_raddr1);
    assign load_hazard_2 = raddr2_use && exe_is_load && exe_write && (exe_rd === rf_raddr2);
    assign hazard = load_hazard_1 || load_hazard_2;

    assign id_ready_go = ~hazard;
    assign id_allow_in = !id_valid || (id_ready_go && exe_allow_in);
    assign id_to_exe_valid = id_valid && id_ready_go;

    always @(posedge clk) begin
        if (reset) begin
            id_valid <= 1'b0;
        end else if (mispredict) begin
            id_valid <= 1'b0;
        end else if (id_allow_in) begin
            id_valid <= if_to_id_valid;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            id_reg <= {`IF_TO_ID_BUS_WIDTH{1'b0}};
        end else if (mispredict) begin
            id_reg <= {`IF_TO_ID_BUS_WIDTH{1'b0}};
        end else if (id_allow_in && if_to_id_valid) begin
            id_reg <= if_to_id_bus;
        end
    end

endmodule
