`include "mycpu_top.h"

module cpu (
    input  wire        clk,
    input  wire        resetn,
    // inst sram interface
    output wire        inst_sram_en,
    output wire [31:0] inst_sram_addr,
    input  wire [31:0] inst_sram_rdata,
    // data sram interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_wen,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire        debug_wb_rf_wen,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,
    // branch prediction statistics interface
    output wire [31:0] branch_total_count,
    output wire [31:0] branch_correct_count
);
    reg reset;
    always @(posedge clk) reset <= ~resetn;
    // wire reset = ~resetn;

    wire [`IF_TO_ID_BUS_WIDTH-1:0] if_to_id_bus;
    wire [`ID_TO_IF_BUS_WIDTH-1:0] id_to_if_bus;
    wire [`ID_TO_EXE_BUS_WIDTH-1:0] id_to_exe_bus;
    wire [`EXE_TO_MEM_BUS_WIDTH-1:0] exe_to_mem_bus;
    wire [`MEM_TO_WB_BUS_WIDTH-1:0] mem_to_wb_bus;
    wire [`WB_TO_ID_BUS_WIDTH-1:0] wb_to_id_bus;
    wire [`EXE_TO_ID_BUS_WIDTH-1:0] exe_to_id_bus;
    wire [`MEM_TO_ID_BUS_WIDTH-1:0] mem_to_id_bus;

    wire if_to_id_valid;
    wire id_allow_in;
    wire id_to_exe_valid;
    wire exe_allow_in;
    wire exe_to_mem_valid;
    wire mem_allow_in;
    wire mem_to_wb_valid;
    wire wb_allow_in;

    // Internal wires for unused ports
    wire [3:0] inst_sram_we;
    wire [31:0] inst_sram_wdata;
    wire [3:0] debug_wb_rf_we;

    // Branch predictor signals
    wire [31:0] if_pc;
    wire [31:0] pred_next_pc;
    wire        pred_br_taken;
    wire        upd_en;
    wire [31:0] upd_inst_addr;
    wire        upd_br_inst;
    wire        upd_cond_br_inst;
    wire        upd_br_taken;
    wire [31:0] upd_br_target;

    if_stage if_stage (
        .clk(clk),
        .reset(reset),
        .id_allow_in(id_allow_in),
        .if_to_id_valid(if_to_id_valid),
        .if_to_id_bus(if_to_id_bus),
        .id_to_if_bus(id_to_if_bus),
        .inst_sram_en(inst_sram_en),
        .inst_sram_we(inst_sram_we),
        .inst_sram_addr(inst_sram_addr),
        .inst_sram_wdata(inst_sram_wdata),
        .inst_sram_rdata(inst_sram_rdata),
        // Branch predictor interface
        .if_pc(if_pc),
        .pred_next_pc(pred_next_pc),
        .pred_br_taken(pred_br_taken)
    );

    id_stage id_stage (
        .clk(clk),
        .reset(reset),
        .id_allow_in(id_allow_in),
        .if_to_id_valid(if_to_id_valid),
        .exe_allow_in(exe_allow_in),
        .id_to_exe_valid(id_to_exe_valid),
        .if_to_id_bus(if_to_id_bus),
        .id_to_exe_bus(id_to_exe_bus),
        .exe_to_id_bus(exe_to_id_bus),
        .mem_to_id_bus(mem_to_id_bus),
        .id_to_if_bus(id_to_if_bus),
        .wb_to_id_bus(wb_to_id_bus),
        // Branch predictor update interface
        .upd_en(upd_en),
        .upd_inst_addr(upd_inst_addr),
        .upd_br_inst(upd_br_inst),
        .upd_cond_br_inst(upd_cond_br_inst),
        .upd_br_taken(upd_br_taken),
        .upd_br_target(upd_br_target)
    );

    exe_stage exe_stage (
        .clk(clk),
        .reset(reset),
        .exe_allow_in(exe_allow_in),
        .id_to_exe_valid(id_to_exe_valid),
        .mem_allow_in(mem_allow_in),
        .exe_to_mem_valid(exe_to_mem_valid),
        .id_to_exe_bus(id_to_exe_bus),
        .exe_to_mem_bus(exe_to_mem_bus),
        .exe_to_id_bus(exe_to_id_bus),
        .data_sram_en(data_sram_en),
        .data_sram_we(data_sram_wen),
        .data_sram_addr(data_sram_addr),
        .data_sram_wdata(data_sram_wdata)
    );

    mem_stage mem_stage (
        .clk(clk),
        .reset(reset),
        .mem_allow_in(mem_allow_in),
        .exe_to_mem_valid(exe_to_mem_valid),
        .wb_allow_in(wb_allow_in),
        .mem_to_wb_valid(mem_to_wb_valid),
        .exe_to_mem_bus(exe_to_mem_bus),
        .mem_to_wb_bus(mem_to_wb_bus),
        .mem_to_id_bus(mem_to_id_bus),
        // .data_sram_en(data_sram_en),
        // .data_sram_we(data_sram_wen),
        // .data_sram_addr(data_sram_addr),
        // .data_sram_wdata(data_sram_wdata)
        .data_sram_rdata(data_sram_rdata)
    );

    wb_stage wb_stage (
        .clk(clk),
        .reset(reset),
        .wb_allow_in(wb_allow_in),
        .mem_to_wb_valid(mem_to_wb_valid),
        .mem_to_wb_bus(mem_to_wb_bus),
        .wb_to_id_bus(wb_to_id_bus),
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_we(debug_wb_rf_we),
        .debug_wb_rf_wnum(debug_wb_rf_wnum),
        .debug_wb_rf_wdata(debug_wb_rf_wdata)
    );

    assign debug_wb_rf_wen = debug_wb_rf_we[0];

    // Branch predictor instantiation
    my_branch_predictor branch_predictor (
        .clk(clk),
        .reset(reset),
        // Prediction interface (for IF stage)
        .pc(if_pc),
        .pred_next_pc(pred_next_pc),
        .pred_br_taken(pred_br_taken),
        // Update interface (from ID stage)
        .upd_en(upd_en),
        .upd_inst_addr(upd_inst_addr),
        .upd_br_inst(upd_br_inst),
        .upd_cond_br_inst(upd_cond_br_inst),
        .upd_br_taken(upd_br_taken),
        .upd_br_target(upd_br_target),
        // Statistics interface
        .branch_total_count(branch_total_count),
        .branch_correct_count(branch_correct_count)
    );

endmodule
