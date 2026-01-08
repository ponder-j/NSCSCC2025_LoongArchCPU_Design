`include "mycpu_top.h"

module if_stage (
    input clk,
    input reset,

    // pipeline control
    input id_allow_in,
    output if_to_id_valid,

    // bus to id
    output [`IF_TO_ID_BUS_WIDTH-1:0] if_to_id_bus,

    // bus from id
    input [`ID_TO_IF_BUS_WIDTH-1:0] id_to_if_bus,

    // cpu interface
    output        inst_sram_en,    // instruction memory enable
    output [ 3:0] inst_sram_we,    // instruction memory write enable
    output [31:0] inst_sram_addr,  // instruction memory address
    output [31:0] inst_sram_wdata, // instruction memory write data
    input  [31:0] inst_sram_rdata, // instruction memory read data

    // branch predictor interface
    output [31:0] if_pc,           // current PC (for predictor)
    input  [31:0] pred_next_pc,    // predicted next PC
    input         pred_br_taken    // predicted branch taken
);

    // input bus from ID (for branch)
    wire        br_taken;
    wire [31:0] br_target;
    assign {br_taken, br_target} = id_to_if_bus;

    // output bus to ID
    reg  [31:0] if_pc_reg;
    wire [31:0] inst;
    reg         if_pred_br_taken;  // Store prediction for ID stage
    assign if_to_id_bus = {if_pred_br_taken, if_pc_reg, inst};
    assign if_pc = if_pc_reg;

    // internal signals
    wire [31:0] seq_pc;
    wire [31:0] nextpc;

    // pipeline control
    reg if_valid;
    wire if_ready_go;
    wire if_allow_in;
    wire pre_if_valid;

    always @(posedge clk) begin
      if (reset) begin
        if_valid <= 1'b0;
      end else if (if_allow_in) begin
        if_valid <= pre_if_valid;
      end
    end

    // pre-IF stage
    assign seq_pc  = if_pc_reg + 3'h4;
    // Modified PC update logic with branch prediction
    // Priority: br_taken (misprediction correction) > pred_br_taken (prediction) > seq_pc (sequential)
    assign nextpc  = br_taken ? br_target :
                     pred_br_taken ? pred_next_pc :
                     seq_pc;
    assign pre_if_valid = ~reset; 

    // IF stage
    assign if_ready_go = 1;
    assign if_to_id_valid = if_valid && if_ready_go;
    assign if_allow_in = !if_valid || (if_ready_go && id_allow_in);

    always @(posedge clk) begin
        if (reset) begin
            if_pc_reg <= 32'hfffffffc;
            if_pred_br_taken <= 1'b0;
        end else if (if_allow_in && pre_if_valid) begin
            if_pc_reg <= nextpc;
            if_pred_br_taken <= pred_br_taken;
        end
    end

    assign inst_sram_en    = pre_if_valid && if_allow_in;
    assign inst_sram_we    = 4'b0000;
    assign inst_sram_addr  = nextpc;
    assign inst_sram_wdata = 32'b0;
    assign inst            = inst_sram_rdata;


endmodule