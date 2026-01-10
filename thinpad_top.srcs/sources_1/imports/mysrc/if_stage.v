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
    output wire        inst_sram_req    ,  // 指令存储器请求信号，为1时表示本次请求有效，为0时表示无效
    output wire [31:0] inst_sram_addr   ,  // 指令存储器请求的地址
    input  wire        inst_sram_addr_ok,  // 指令存储器地址握手信号，表示本次传输地址被接收
    input  wire        inst_sram_data_ok,  // 指令存储器数据有效信号，表示本次返回数据有效 
    input  wire [31:0] inst_sram_rdata  ,  // 指令存储器读数据

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

    // IF Stage Buffer
    reg [31:0] if_inst_buf;      // 临时保存指令内容
    reg        if_inst_buf_valid;// 标记 Buffer 是否有效

    // internal signals
    wire [31:0] seq_pc;
    wire [31:0] nextpc;

    // pipeline control
    reg if_valid;
    wire if_ready_go;
    wire if_allow_in;
    wire pre_if_valid;
    wire pre_if_ready_go;

    assign pre_if_ready_go = inst_sram_req && inst_sram_addr_ok;

    always @(posedge clk) begin
      if (reset) begin
        if_valid <= 1'b0;
      end else if (if_allow_in) begin
        if_valid <= pre_if_ready_go;
      end
    end


    // ---------------------------------------------------------
    // Buffer 管理逻辑
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            if_inst_buf_valid <= 1'b0;
            if_inst_buf       <= 32'b0;
        end else if (inst_sram_data_ok && !if_inst_buf_valid && !id_allow_in) begin
            // 场景：数据回来了(data_ok)，Buffer是空的，但ID不收(!id_allow_in)
            // 动作：必须把数据锁存起来，否则下一拍就没了
            if_inst_buf_valid <= 1'b1;
            if_inst_buf       <= inst_sram_rdata;
        end else if (id_allow_in && if_ready_go) begin
            // 场景：ID终于收了数据
            // 动作：Buffer 任务完成，标记无效
            if_inst_buf_valid <= 1'b0;
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
    // 1. 如果数据刚从 SRAM 回来 (data_ok) -> Ready
    // 2. 或者数据已经在 Buffer 里存着了 (buf_valid) -> Ready
    assign if_ready_go    = inst_sram_data_ok || if_inst_buf_valid;

    // 如果 Buffer 有效，就从 Buffer 读；否则直接从 SRAM 接口读
    assign inst           = if_inst_buf_valid ? if_inst_buf : inst_sram_rdata;

    assign if_to_id_valid = if_valid && if_ready_go;
    assign if_allow_in    = !if_valid || (if_ready_go && id_allow_in);

    always @(posedge clk) begin
        if (reset) begin
            if_pc_reg <= 32'h7ffffffc;
            if_pred_br_taken <= 1'b0;
        end else if (if_allow_in && pre_if_ready_go) begin
            if_pc_reg <= nextpc;
            if_pred_br_taken <= pred_br_taken;
        end
    end

    assign inst_sram_req   = if_allow_in && pre_if_valid;
    assign inst_sram_addr  = nextpc;

endmodule