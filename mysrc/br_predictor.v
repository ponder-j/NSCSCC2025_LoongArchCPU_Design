module my_branch_predictor(
    input clk,
    input reset,

    // 供 CPU IF 段使用的接口：
    input  [31:0] pc,              // 当前指令地址
    output [31:0] pred_next_pc,    // 预测出的下一个指令地址
    output        pred_br_taken,   // 是否被预测为执行转移的转移指令

    // 分支预测器更新接口：
    input        upd_en,           // 更新使能
    input [31:0] upd_inst_addr,    // 转移指令地址
    input        upd_br_inst,      // 是否为转移指令
    input        upd_cond_br_inst, // 是否为条件转移指令
    input        upd_br_taken,     // 转移指令是否真的转移
    input [31:0] upd_br_target,    // 转移指令的真实目标地址

    // 分支预测统计接口：
    output [31:0] branch_total_count,   // 分支指令总数
    output [31:0] branch_correct_count  // 分支预测正确次数
);

    // ====== 参数定义 ======
    parameter INDEX_WIDTH = 8;  // 使用8位索引，有256个表项
    parameter TABLE_SIZE = 1 << INDEX_WIDTH;  // 2^8 = 256
    parameter TAG_WIDTH = 22;   // 标签宽度 pc[31:10]

    // ====== BTB表 256 项 ======
    // valid 1 | is_branch 1 | tag 22 | target 32
    reg                      BTB_valid     [TABLE_SIZE-1:0];  // 有效位
    reg                      BTB_is_branch [TABLE_SIZE-1:0];  // 是否为转移指令
    reg [TAG_WIDTH-1:0]      BTB_tag       [TABLE_SIZE-1:0];  // 指令地址标签
    reg [31:0]               BTB_target    [TABLE_SIZE-1:0];  // 转移目标地址

    // ====== BPB表 256 项 ======
    // 2 位饱和计数器
    // 00: 强不跳转, 01: 弱不跳转, 10: 弱跳转, 11: 强跳转
    reg [1:0] BPB [TABLE_SIZE-1:0];

    // ====== 分支预测统计计数器 ======
    reg [31:0] total_count;     // 分支指令总数
    reg [31:0] correct_count;   // 分支预测正确次数

    assign branch_total_count = total_count;
    assign branch_correct_count = correct_count;

    // ====== 索引生成 ======
    // 使用PC的[9:2]位作为索引
    wire [INDEX_WIDTH-1:0] pc_index;
    wire [INDEX_WIDTH-1:0] upd_index;

    // 使用PC的[31:10]位作为标签
    wire [TAG_WIDTH-1:0] pc_tag;
    wire [TAG_WIDTH-1:0] upd_tag;

    assign pc_index  = pc[INDEX_WIDTH+1:2];            // 提取 pc_index 用于预测
    assign upd_index = upd_inst_addr[INDEX_WIDTH+1:2]; // 提取 upd_index 用于更新
    assign pc_tag    = pc[31:10];
    assign upd_tag   = upd_inst_addr[31:10];

    // ====== 预测逻辑 ======
    // 1. 查询BTB，检查是否命中
    wire btb_hit;
    wire btb_is_branch;
    wire [31:0] btb_target;

    assign btb_hit = BTB_valid[pc_index] 
                    && (BTB_tag[pc_index] == pc_tag); // 表项有效且 tag 匹配
    assign btb_is_branch = BTB_is_branch[pc_index];
    assign btb_target = BTB_target[pc_index];         // 获取预测目标地址

    // 2. 查询BPB，获取2位预测状态
    wire [1:0] bpb_state;
    wire       bpb_predict_taken;

    assign bpb_state = BPB[pc_index];         // 获取 2 位饱和计数器状态
    assign bpb_predict_taken = bpb_state[1];  // 最高位为 1 表示预测跳转

    // 3. 综合判断：BTB命中 && 是分支指令 && BPB预测跳转
    assign pred_br_taken = btb_hit && btb_is_branch && bpb_predict_taken;

    // 4. 输出预测的下一个PC
    assign pred_next_pc = pred_br_taken ? btb_target : (pc + 32'h4);

    // ====== 分支预测准确性判断逻辑 ======
    // 用于统计分支预测的准确率
    // 根据更新信号判断之前的预测是否正确
    wire upd_btb_hit;
    wire upd_bpb_predict_taken;
    wire upd_pred_br_taken;
    wire pred_correct;

    assign upd_btb_hit = BTB_valid[upd_index] && (BTB_tag[upd_index] == upd_tag);
    assign upd_bpb_predict_taken = BPB[upd_index][1];  // 最高位为1表示预测跳转
    // 重构之前的预测：BTB命中 && 是分支指令 && BPB预测跳转
    assign upd_pred_br_taken = upd_btb_hit && BTB_is_branch[upd_index] && upd_bpb_predict_taken;
    // 预测正确：预测结果 == 实际结果
    assign pred_correct = (upd_pred_br_taken == upd_br_taken);

    // ====== BTB和BPB更新逻辑 ======
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            // 复位：清空BTB和BPB
            for (i = 0; i < TABLE_SIZE; i = i + 1) begin
                BTB_valid[i] <= 1'b0;
                BTB_is_branch[i] <= 1'b0;
                BTB_tag[i] <= {TAG_WIDTH{1'b0}};
                BTB_target[i] <= 32'h0;
                BPB[i] <= 2'b01;  // 初始化为弱不跳转
            end
            // 复位：清空统计计数器
            total_count <= 32'h0;
            correct_count <= 32'h0;
        end else if (upd_en && upd_br_inst) begin
            // 更新BTB表项（所有分支指令）
            BTB_valid[upd_index] <= 1'b1;
            BTB_is_branch[upd_index] <= 1'b1;
            BTB_tag[upd_index] <= upd_tag;
            BTB_target[upd_index] <= upd_br_target;

            // 更新BPB的2位饱和计数器
            if (upd_cond_br_inst) begin
                // 更新统计计数器
                total_count <= total_count + 32'h1;
                if (pred_correct) begin
                    correct_count <= correct_count + 32'h1;
                end
                // 条件分支：正常的饱和计数器更新
                if (upd_br_taken) begin
                    // 实际跳转：计数器增加（饱和到11）
                    if (BPB[upd_index] != 2'b11)
                        BPB[upd_index] <= BPB[upd_index] + 2'b01;
                end else begin
                    // 实际不跳转：计数器减少（饱和到00）
                    if (BPB[upd_index] != 2'b00)
                        BPB[upd_index] <= BPB[upd_index] - 2'b01;
                end
            end else begin
                // 无条件分支：直接设置为强跳转
                BPB[upd_index] <= 2'b11;
            end
        end
    end

endmodule