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
    output wire        inst_sram_req    , 
    output wire [31:0] inst_sram_addr   , 
    input  wire        inst_sram_addr_ok, 
    input  wire        inst_sram_data_ok, 
    input  wire [31:0] inst_sram_rdata  , 

    // branch predictor interface
    output [31:0] if_pc,           
    input  [31:0] pred_next_pc,    
    input         pred_br_taken    
);

    // input bus from ID
    wire        br_taken;
    wire [31:0] br_target;
    assign {br_taken, br_target} = id_to_if_bus;

    // output bus to ID
    reg  [31:0] if_pc_reg;
    wire [31:0] inst;
    reg         if_pred_br_taken; 
    assign if_to_id_bus = {pred_br_taken, if_pc_reg, inst};
    assign if_pc = if_pc_reg;

    // internal signals
    wire [31:0] seq_pc;
    wire [31:0] nextpc;

    // IF Stage Buffer
    reg [31:0] if_inst_buf;
    reg        if_inst_buf_valid;

    // pipeline control
    reg if_valid;
    wire if_ready_go;
    wire if_allow_in;
    wire pre_if_valid;
    wire pre_if_ready_go;

    // ---------------------------------------------------------
    // 关键修正：Request 锁存逻辑
    // ---------------------------------------------------------
    reg        req_pending;     // 标记：请求已发出但被卡住
    reg [31:0] req_addr_buf;    // 缓冲：卡住的那个地址（比如 80002100）

    // 组合逻辑计算出的“本周期想要访问的地址”
    assign seq_pc  = if_pc_reg + 3'h4;
    assign nextpc  = br_taken ? br_target :
                     pred_br_taken ? pred_next_pc :
                     seq_pc;

    always @(posedge clk) begin
        if (reset || nextpc == 32'h80000000) begin
            req_pending <= 1'b0;
            req_addr_buf <= 32'b0;
        end else if (!req_pending || br_taken) begin
            req_addr_buf <= nextpc;
            req_pending <= 1;
        end else if (inst_sram_addr_ok) begin
            // 握手成功，任务完成，清除 pending 状态
            req_pending <= 1'b0;
        end
    end
    
    // ---------------------------------------------------------
    // SRAM 接口信号生成
    // ---------------------------------------------------------
    
    // 1. 请求信号：如果有 pending 的任务，必须持续拉高 req，直到成功
    assign inst_sram_req   = (if_allow_in && pre_if_valid) || req_pending;
    
    // 2. 地址信号（这就是解决问题的关键）：
    // 如果处于 pending 状态（req_pending=1），说明之前的跳转请求（80002100）还没发出去。
    // 此时我们要无视当前的 ID 信号（因为 ID 可能已经变了），强行输出 buffer 里的地址。
    // 只有在非 pending 状态下，才使用组合逻辑算出来的 nextpc。
    assign inst_sram_addr  = req_pending ? req_addr_buf : nextpc;

    assign pre_if_valid    = ~reset; 
    assign pre_if_ready_go = inst_sram_req && inst_sram_addr_ok;

    // ---------------------------------------------------------
    // IF Stage Logic
    // ---------------------------------------------------------
    
    always @(posedge clk) begin
      if (reset) begin
        if_valid <= 1'b0;
      end else if (if_allow_in) begin
        if_valid <= pre_if_ready_go;
      end
    end

    always @(posedge clk) begin
        if (reset) begin
            if_inst_buf_valid <= 1'b0;
            if_inst_buf       <= 32'b0;
        end else if (inst_sram_data_ok && !if_inst_buf_valid && !id_allow_in) begin
            if_inst_buf_valid <= 1'b1;
            if_inst_buf       <= inst_sram_rdata;
        end else if (id_allow_in && if_ready_go) begin
            if_inst_buf_valid <= 1'b0;
        end
    end

    assign if_ready_go    = inst_sram_data_ok || if_inst_buf_valid;
    assign inst           = if_inst_buf_valid ? if_inst_buf : inst_sram_rdata;
    assign if_to_id_valid = if_valid && if_ready_go;
    assign if_allow_in    = !if_valid || (if_ready_go && id_allow_in);

    // ---------------------------------------------------------
    // PC 更新逻辑
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            if_pc_reg <= 32'h7ffffffc; 
            if_pred_br_taken <= 1'b0;
        end else if (if_allow_in && pre_if_ready_go) begin
            // 这里的逻辑也要和 SRAM 地址保持一致
            // 如果握手成功的是一个 pending 的请求，那 PC 也要更新为 pending 的地址
            if_pc_reg <= req_pending ? req_addr_buf : nextpc;
            if_pred_br_taken <= pred_br_taken;
        end
    end

endmodule