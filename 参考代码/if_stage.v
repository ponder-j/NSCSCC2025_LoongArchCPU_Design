`include "cpu.vh"

module if_stage(
    input clk, reset,

    input id_allow_in,
    output if_to_id_valid,

    output [`IF_TO_ID_BUS_WIDTH-1:0] if_to_id_bus,
    input [`ID_TO_IF_BUS_WIDTH-1:0] id_to_if_bus,

    output inst_sram_en,
    output [31:0] inst_sram_addr,
    input [31:0] inst_sram_rdata
);

    wire        redirect_valid;
    wire [31:0] redirect_pc;
    wire        bp_upd_en;
    wire [31:0] bp_upd_inst_addr;
    wire        bp_upd_br_inst;
    wire        bp_upd_cond_br_inst;
    wire        bp_upd_br_taken;
    wire [31:0] bp_upd_br_target;
    assign {redirect_valid,
            redirect_pc,
            bp_upd_en,
            bp_upd_inst_addr,
            bp_upd_br_inst,
            bp_upd_cond_br_inst,
            bp_upd_br_taken,
            bp_upd_br_target} = id_to_if_bus;

    reg [31:0] pc;

    reg        redirect_pending;
    reg [31:0] redirect_pc_r;

    wire [31:0] pred_next_pc;
    wire        pred_br_taken;

    simple_branch_predictor u_branch_predictor(
        .clk              (clk),
        .reset            (reset),
        .pc               (pc),
        .pred_next_pc     (pred_next_pc),
        .pred_br_taken    (pred_br_taken),
        .upd_en           (bp_upd_en),
        .upd_inst_addr    (bp_upd_inst_addr),
        .upd_br_inst      (bp_upd_br_inst),
        .upd_cond_br_inst (bp_upd_cond_br_inst),
        .upd_br_taken     (bp_upd_br_taken),
        .upd_br_target    (bp_upd_br_target)
    );

    always @(posedge clk) begin
        if (reset) begin
            redirect_pending <= 1'b0;
            redirect_pc_r    <= 32'b0;
        end else begin
            if (redirect_valid) begin
                redirect_pending <= 1'b1;
                redirect_pc_r    <= redirect_pc;
            end else if (if_allow_in && redirect_pending) begin
                redirect_pending <= 1'b0;
            end
        end
    end

    wire [31:0] nextpc = redirect_valid      ? redirect_pc   :
                         redirect_pending   ? redirect_pc_r :
                                             pred_next_pc;

    reg [31:0] inst_r;
    wire [31:0] inst = inst_r;

    assign if_to_id_bus = {pred_br_taken, pred_next_pc, pc, inst};

    reg if_valid;
    wire if_allow_in;
    wire if_ready_go;

    always @(posedge clk) begin
        if (reset) begin
            if_valid <= 1'b0;
        end else if (redirect_valid) begin
            if_valid <= 1'b0;
        end else if (if_allow_in) begin
            if_valid <= 1'b1;
        end
    end

    assign if_ready_go = 1'b1;
    assign if_to_id_valid = if_valid && if_ready_go;
    assign if_allow_in = redirect_valid ? 1'b1
                                        : (!if_valid || (if_ready_go && id_allow_in));

    always @(posedge clk) begin
        if (reset) begin
            // Reset trick: make first predicted next PC become 0x8000_0000 (BaseRAM mapped)
            // because simple_branch_predictor uses seq_pc = pc + 4 by default.
            pc <= 32'h7fff_fffc;
        end else if (if_allow_in) begin
            pc <= nextpc;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            inst_r <= 32'b0;
        end else if (if_allow_in) begin
            inst_r <= inst_sram_rdata;
        end
    end

    assign inst_sram_addr = nextpc;
    assign inst_sram_en   = !reset && if_allow_in;

endmodule
