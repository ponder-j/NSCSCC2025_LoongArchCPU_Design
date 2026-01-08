`include "mycpu_top.h"

module id_stage(
    input clk,
    input reset,

    // pipeline control
    output id_allow_in,
    input  if_to_id_valid,
    input  exe_allow_in,
    output id_to_exe_valid,

    // bus from if
    input [`IF_TO_ID_BUS_WIDTH-1:0] if_to_id_bus,

    // bus to exe
    output [`ID_TO_EXE_BUS_WIDTH-1:0] id_to_exe_bus,

    // buses from downstream stages (hazard detect)
    input [`EXE_TO_ID_BUS_WIDTH-1:0] exe_to_id_bus,
    input [`MEM_TO_ID_BUS_WIDTH-1:0] mem_to_id_bus,

    // bus to if (for branch)
    output [`ID_TO_IF_BUS_WIDTH-1:0] id_to_if_bus,

    // bus from wb (for regfile)
    input [`WB_TO_ID_BUS_WIDTH-1:0] wb_to_id_bus,

    // branch predictor update interface
    output        upd_en,
    output [31:0] upd_inst_addr,
    output        upd_br_inst,
    output        upd_cond_br_inst,
    output        upd_br_taken,
    output [31:0] upd_br_target
);

    // pipeline registers
    reg [`IF_TO_ID_BUS_WIDTH-1:0] id_reg;
    wire [31:0] id_pc;
    // wire [31:0] id_inst_XX;
    wire [31:0] id_inst;
    wire        id_pred_br_taken_X;  // prediction from IF stage
    assign {id_pred_br_taken_X, id_pc, id_inst} = id_reg;
    assign id_pred_br_taken = if_to_id_bus[64]; // 预测结果直接从 IF 传递过来
    // assign id_inst = if_to_id_bus[31:0]; // 因为是同步读 RAM，所以从 id_reg 读到的 inst 是慢了一拍的，应该直接从 if_to_id_bus 取

    // input bus from WB (for regfile)
    wire        wb_valid;
    wire        wb_rf_we_raw;
    wire [4:0]  wb_rf_waddr;
    wire [31:0] wb_rf_wdata;
    assign {wb_valid, wb_rf_we_raw, wb_rf_waddr, wb_rf_wdata} = wb_to_id_bus;

    wire        exe_valid;
    wire        exe_rf_we_raw;
    wire [4:0]  exe_rf_waddr;
    wire [31:0] exe_rf_wdata;
    wire        exe_is_load;
    assign {exe_valid, exe_rf_we_raw, exe_rf_waddr, exe_rf_wdata, exe_is_load} = exe_to_id_bus;
    wire exe_rf_we = exe_valid && exe_rf_we_raw;

    wire        mem_valid;
    wire        mem_rf_we_raw;
    wire [4:0]  mem_rf_waddr;
    wire [31:0] mem_rf_wdata;
    assign {mem_valid, mem_rf_we_raw, mem_rf_waddr, mem_rf_wdata} = mem_to_id_bus;
    wire mem_rf_we = mem_valid && mem_rf_we_raw;

    wire wb_rf_we = wb_valid && wb_rf_we_raw;

    // output bus to EXE
    wire [31:0] rj_value;
    wire [31:0] rkd_value;
    wire [31:0] imm;
    wire [11:0] alu_op;
    wire        src1_is_pc;
    wire        src2_is_imm;
    wire        res_from_mem;
    wire        reg_we;
    wire        mem_en;
    wire [3:0]  mem_we;
    wire [4:0]  reg_waddr;

    assign id_to_exe_bus = {
        id_pc,       
        rj_value,    // Rj 寄存器读出的操作数
        rkd_value,   // Rk 或 Rd 读出的第二个操作数
        imm,         // 立即数扩展结果
        alu_op,      // 送往 ALU 的控制码
        src1_is_pc,  // 选择 PC 作为 ALU 源 1
        src2_is_imm, // 选择立即数作为 ALU 源 2
        res_from_mem,// EXE 结果来自访存
        reg_we,      // 是否写回寄存器
        mem_en,      // 是否启用数据存储器
        mem_we,      // 数据存储器写使能
        reg_waddr    // 写回寄存器地址
    };

    // output bus to IF (for branch)
    wire        actual_br_taken;
    wire        br_cancel;
    wire [31:0] br_target;
    wire [31:0] actual_br_target;
    assign id_to_if_bus = {actual_br_taken, actual_br_target};

    // pipeline control
    reg  id_valid;
    wire id_ready_go;

    // hazard detection
    wire use_rf_rdata1 = id_valid && (
        inst_add_w   || inst_sub_w   || inst_slt   || inst_sltu ||
        inst_nor     || inst_and     || inst_or    || inst_mul  ||
        inst_slli_w  || inst_srli_w  || inst_srai_w ||
        inst_addi_w  || inst_ori     || inst_slti  ||
        inst_ld_w    || inst_st_w    || inst_jirl  ||
        inst_beq     || inst_bne
    );
    wire use_rf_rdata2 = id_valid && (
        inst_add_w   || inst_sub_w   || inst_slt   || inst_sltu ||
        inst_nor     || inst_and     || inst_or    || inst_mul  ||
        inst_st_w    || inst_beq     || inst_bne
    );

    // 不需要对 reg0 进行特判，因为已经在 assign reg_we 这句里实现
    // wire rf_rdata1_hazard = use_rf_rdata1 && (
    //     (exe_rf_we && (rf_raddr1 == exe_rf_waddr)) ||
    //     (mem_rf_we && (rf_raddr1 == mem_rf_waddr)) ||
    //     (wb_rf_we  && (rf_raddr1 == wb_rf_waddr))
    // );
    // wire rf_rdata2_hazard = use_rf_rdata2 && (
    //     (exe_rf_we && (rf_raddr2 == exe_rf_waddr)) ||
    //     (mem_rf_we && (rf_raddr2 == mem_rf_waddr)) ||
    //     (wb_rf_we  && (rf_raddr2 == wb_rf_waddr))
    // );
    // 添加旁路控制，冲突的情况减少到 2 种
    wire rf_rdata1_hazard = use_rf_rdata1 && (
        exe_valid && exe_is_load && exe_rf_we && (rf_raddr1 == exe_rf_waddr)
    );
    wire rf_rdata2_hazard = use_rf_rdata2 && (
        exe_valid && exe_is_load && exe_rf_we && (rf_raddr2 == exe_rf_waddr)
    );

    assign id_ready_go = !rf_rdata1_hazard && !rf_rdata2_hazard;
    assign id_allow_in = !id_valid || id_ready_go && exe_allow_in;
    assign id_to_exe_valid = id_valid && id_ready_go;

    always @(posedge clk) begin
        if (reset) begin
            id_valid <= 1'b0;
        end else if (br_cancel) begin
            id_valid <= 1'b0;
        end else if (id_allow_in) begin
            id_valid <= if_to_id_valid;
        end
    end

    always @(posedge clk) begin
        if (id_allow_in && if_to_id_valid) begin
            id_reg <= if_to_id_bus;
        end
    end

    // internal signals
    wire        dst_is_r1;
    wire        src_reg_is_rd;
    wire [31:0] br_offs;
    wire [31:0] jirl_offs;

    wire [5:0]  op_31_26;
    wire [3:0]  op_25_22;
    wire [1:0]  op_21_20;
    wire [4:0]  op_19_15;
    wire [4:0]  rd;
    wire [4:0]  rj;
    wire [4:0]  rk;
    wire [11:0] i12;
    wire [19:0] i20;
    wire [15:0] i16;
    wire [25:0] i26;

    wire [63:0] op_31_26_d;
    wire [15:0] op_25_22_d;
    wire [3:0]  op_21_20_d;
    wire [31:0] op_19_15_d;

    wire        inst_add_w;
    wire        inst_sub_w;
    wire        inst_slt;
    wire        inst_sltu;
    wire        inst_nor;
    wire        inst_and;
    wire        inst_or;
    wire        inst_mul;
    wire        inst_slli_w;
    wire        inst_srli_w;
    wire        inst_srai_w;
    wire        inst_addi_w;
    wire        inst_ori;
    wire        inst_slti;
    wire        inst_ld_w;
    wire        inst_st_w;
    wire        inst_jirl;
    wire        inst_b;
    wire        inst_bl;
    wire        inst_beq;
    wire        inst_bne;
    wire        inst_lu12i_w;

    wire        need_ui5;
    wire        need_si12;
    wire        need_ui12;
    wire        need_si16;
    wire        need_si20;
    wire        need_si26;
    wire        src2_is_4;

    wire [4:0]  rf_raddr1;
    wire [31:0] rf_rdata1;
    wire [4:0]  rf_raddr2;
    wire [31:0] rf_rdata2;
    wire        rf_we;
    wire [4:0]  rf_waddr;
    wire [31:0] rf_wdata;

    // ID stage
    assign op_31_26 = id_inst[31:26];
    assign op_25_22 = id_inst[25:22];
    assign op_21_20 = id_inst[21:20];
    assign op_19_15 = id_inst[19:15];
    assign rd   = id_inst[4:0];
    assign rj   = id_inst[9:5];
    assign rk   = id_inst[14:10];
    assign i12  = id_inst[21:10];
    assign i20  = id_inst[24:5];
    assign i16  = id_inst[25:10];
    assign i26  = {id_inst[9:0], id_inst[25:10]};

    decoder_6_64 u_dec0 (
        .in (op_31_26),
        .out(op_31_26_d)
    );

    decoder_4_16 u_dec1 (
        .in (op_25_22),
        .out(op_25_22_d)
    );

    decoder_2_4 u_dec2 (
        .in (op_21_20),
        .out(op_21_20_d)
    );

    decoder_5_32 u_dec3 (
        .in (op_19_15),
        .out(op_19_15_d)
    );

    assign inst_add_w    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
    assign inst_sub_w    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
    assign inst_slt      = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
    assign inst_sltu     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
    assign inst_nor      = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
    assign inst_and      = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
    assign inst_or       = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
    assign inst_mul      = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
    assign inst_slli_w   = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
    assign inst_srli_w   = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
    assign inst_srai_w   = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
    assign inst_addi_w   = op_31_26_d[6'h00] & op_25_22_d[4'ha];
    assign inst_ori      = op_31_26_d[6'h00] & op_25_22_d[4'he];
    assign inst_ld_w     = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
    assign inst_st_w     = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
    assign inst_slti     = op_31_26_d[6'h00] & op_25_22_d[4'h8];
    assign inst_jirl     = op_31_26_d[6'h13];
    assign inst_b        = op_31_26_d[6'h14];
    assign inst_bl       = op_31_26_d[6'h15];
    assign inst_beq      = op_31_26_d[6'h16];
    assign inst_bne      = op_31_26_d[6'h17];
    assign inst_lu12i_w  = op_31_26_d[6'h05] & ~id_inst[25];

    assign alu_op[0]  = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w | inst_jirl | inst_bl; // add
    assign alu_op[1]  = inst_sub_w; // sub
    assign alu_op[2]  = inst_slt | inst_slti;   // slt
    assign alu_op[3]  = inst_sltu;  // sltu
    assign alu_op[4]  = inst_and;   // and
    assign alu_op[5]  = inst_nor;   // nor
    assign alu_op[6]  = inst_or | inst_ori;    // or
    assign alu_op[7]  = inst_mul;   // mul
    assign alu_op[8]  = inst_slli_w;// sll
    assign alu_op[9]  = inst_srli_w;// srl
    assign alu_op[10] = inst_srai_w;// sra
    assign alu_op[11] = inst_lu12i_w;// lui

    assign need_ui5  = inst_slli_w | inst_srli_w | inst_srai_w;
    assign need_si12 = inst_addi_w | inst_ld_w | inst_st_w | inst_slti;
    assign need_si16 = inst_jirl | inst_beq | inst_bne;
    assign need_si20 = inst_lu12i_w;
    assign need_si26 = inst_b | inst_bl;
    assign src2_is_4 = inst_jirl | inst_bl;
    assign need_ui12 = inst_ori;

    assign imm = src2_is_4 ? 32'h4 :
                 need_si20 ? {i20[19:0], 12'b0} :
                 need_ui12 ? {20'b0, i12[11:0]} :
                 /*need_ui5 || need_si12*/{{20{i12[11]}}, i12[11:0]};

    assign br_offs = need_si26 ? {{4{i26[25]}}, i26[25:0], 2'b0} : {{14{i16[15]}}, i16[15:0], 2'b0};
    assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

    assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w;
    assign src1_is_pc = inst_jirl | inst_bl;

    assign src2_is_imm = inst_slli_w |
                     inst_srli_w |
                     inst_srai_w |
                     inst_addi_w |
                     inst_ld_w |
                     inst_st_w |
                     inst_lu12i_w |
                     inst_jirl |
                     inst_bl |
                     inst_ori |
                     inst_slti;

    assign res_from_mem = inst_ld_w;
    assign dst_is_r1 = inst_bl;
    assign reg_waddr = dst_is_r1 ? 5'd1 : rd;
    assign reg_we = (~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b) && |(reg_waddr);

    assign mem_en = inst_ld_w || inst_st_w;
    assign mem_we = {4{inst_st_w}};

    assign rf_raddr1 = rj;
    assign rf_raddr2 = src_reg_is_rd ? rd : rk;

    regfile u_regfile (
        .clk    (clk),
        .raddr1 (rf_raddr1),
        .rdata1 (rf_rdata1),
        .raddr2 (rf_raddr2),
        .rdata2 (rf_rdata2),
        .we     (rf_we),
        .waddr  (rf_waddr),
        .wdata  (rf_wdata)
    );

    // bypass
    assign rj_value = 
        (exe_valid && exe_rf_we && (rf_raddr1 == exe_rf_waddr)) ? exe_rf_wdata :
        (mem_valid && mem_rf_we && (rf_raddr1 == mem_rf_waddr)) ? mem_rf_wdata :
        (wb_valid  && wb_rf_we  && (rf_raddr1 == wb_rf_waddr )) ? wb_rf_wdata  :
        rf_rdata1;
    assign rkd_value = 
        (exe_valid && exe_rf_we && (rf_raddr2 == exe_rf_waddr)) ? exe_rf_wdata :
        (mem_valid && mem_rf_we && (rf_raddr2 == mem_rf_waddr)) ? mem_rf_wdata :
        (wb_valid  && wb_rf_we  && (rf_raddr2 == wb_rf_waddr )) ? wb_rf_wdata  :
        rf_rdata2;

    wire rj_eq_rd = (rj_value === rkd_value);

    // Calculate actual branch result
    wire br_taken;
    wire inst_is_br;
    wire inst_is_cond_br;

    assign inst_is_br = inst_beq || inst_bne || inst_jirl || inst_bl || inst_b;
    assign inst_is_cond_br = inst_beq || inst_bne;

    assign br_taken = id_valid && ( inst_beq && rj_eq_rd
                    || inst_bne && !rj_eq_rd
                    || inst_jirl
                    || inst_bl
                    || inst_b
                    );

    // Branch target calculation
    assign br_target = ((inst_beq || inst_bne || inst_bl || inst_b) ? (id_pc + br_offs) :
                    /*inst_jirl*/ (rj_value + jirl_offs));
    
    assign actual_br_target = (br_taken && !id_pred_br_taken) ? br_target:
                                (id_pc + 32'h4);

    // Branch misprediction detection
    wire br_mispred;
    assign br_mispred = (br_taken != id_pred_br_taken);

    // actual_br_taken means "misprediction that needs PC correction"
    assign actual_br_taken = id_valid && id_ready_go && br_mispred;
    assign br_cancel = actual_br_taken;

    // Branch predictor update interface
    assign upd_en = id_valid && id_ready_go && inst_is_br;
    assign upd_inst_addr = id_pc;
    assign upd_br_inst = inst_is_br;
    assign upd_cond_br_inst = inst_is_cond_br;
    assign upd_br_taken = br_taken;
    assign upd_br_target = br_target;

    assign rf_we    = wb_rf_we;
    assign rf_waddr = wb_rf_waddr;
    assign rf_wdata = wb_rf_wdata;

endmodule

