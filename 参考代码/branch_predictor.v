`include "cpu.vh"

module simple_branch_predictor #(
	parameter BTB_INDEX_BITS = 6,  // 64-entry BTB
	parameter BHT_INDEX_BITS = 8   // 256-entry BHT
)(
	input  wire        clk,
	input  wire        reset,

	input  wire [31:0] pc,
	output wire [31:0] pred_next_pc,
	output wire        pred_br_taken,

	input  wire        upd_en,
	input  wire [31:0] upd_inst_addr,
	input  wire        upd_br_inst,
	input  wire        upd_cond_br_inst,
	input  wire        upd_br_taken,
	input  wire [31:0] upd_br_target
);
	//-------------------------------------------------------------------------------------------------
	// 簡易分支预测 (BTB + BHT) 说明（中文注释）
	// - BTB (Branch Target Buffer) 用于准确记住某个 PC 的跳转目标地址（btb_target）和是否为条件分支
	//   (btb_is_cond)，并通过 tag 判断是否命中（btb_valid + tag match）。
	// - BHT (Branch History Table) 使用 2-bit 饱和计数器记录分支偏好（taken/not-taken），
	//   通过索引 bht_idx（通常使用 PC 的若干低位）选取历史状态，配合 BTB 判断是否预测 taken。
	// - pred_next_pc 的逻辑：若 BTB 命中且条目（若为条件分支）被预测 taken，则返回 btb_target；否则返回 seq_pc（PC+4）。
	// - 当 ID 的 upd_en 置位时，会把 ID 计算出来的真实分支信息（包括实际 taken/target）写回到 BTB/BHT 中以更新预测器状态。
	//-------------------------------------------------------------------------------------------------

	localparam BTB_ENTRIES   = 1 << BTB_INDEX_BITS;
	localparam BTB_TAG_WIDTH = 32 - BTB_INDEX_BITS - 2;
	localparam BHT_ENTRIES   = 1 << BHT_INDEX_BITS;

	reg [BTB_TAG_WIDTH-1:0] btb_tag     [0:BTB_ENTRIES-1];
	reg [31:0]              btb_target  [0:BTB_ENTRIES-1];
	reg                     btb_valid   [0:BTB_ENTRIES-1];
	reg                     btb_is_cond [0:BTB_ENTRIES-1];

	reg [1:0] bht [0:BHT_ENTRIES-1];

	integer i;

	// 根据 PC 提取索引用于访问 BTB/BHT：使用 [..+1:2] 去除字对齐后最低两位
	wire [BTB_INDEX_BITS-1:0] btb_idx = pc[BTB_INDEX_BITS+1:2];
	wire [BTB_TAG_WIDTH-1:0]  pc_tag  = pc[31:BTB_INDEX_BITS+2];
	wire [BHT_INDEX_BITS-1:0] bht_idx = pc[BHT_INDEX_BITS+1:2];

	// 判断 BTB 是否命中：需要该 idx 的 entry 有效并且 tag 匹配
	wire btb_hit      = btb_valid[btb_idx] && (btb_tag[btb_idx] == pc_tag);
	wire entry_is_cond= btb_is_cond[btb_idx];
	wire [1:0] bht_state = bht[bht_idx];

	wire [31:0] seq_pc = pc + 32'd4;

	wire cond_taken = bht_state[1];
	wire hit_taken = btb_hit && (entry_is_cond ? cond_taken : 1'b1);

	// 输出预测结果：pred_br_taken 告知外部是否预测为 taken，pred_next_pc 给出预测跳转目标或 seq_pc
	assign pred_br_taken = hit_taken;
	assign pred_next_pc  = hit_taken ? btb_target[btb_idx] : seq_pc;

	wire [BTB_INDEX_BITS-1:0] upd_btb_idx = upd_inst_addr[BTB_INDEX_BITS+1:2];
	wire [BTB_TAG_WIDTH-1:0]  upd_tag     = upd_inst_addr[31:BTB_INDEX_BITS+2];
	wire [BHT_INDEX_BITS-1:0] upd_bht_idx = upd_inst_addr[BHT_INDEX_BITS+1:2];

	always @(posedge clk) begin
		if (reset) begin
			for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
				btb_valid[i]   <= 1'b0;
				btb_tag[i]     <= {BTB_TAG_WIDTH{1'b0}};
				btb_target[i]  <= 32'b0;
				btb_is_cond[i] <= 1'b0;
			end
			// 初始化 BHT 为弱 not-taken（01），这样分支在第一次遇到时不会导致强制跳转
			for (i = 0; i < BHT_ENTRIES; i = i + 1) begin
				bht[i] <= 2'b01; // weakly not taken after reset
			end
		end else begin
			// predictor 更新逻辑：当 ID 提供 upd_en 并且该指令为跳转（upd_br_inst），
			// 将 BTB 条目写入 target、tag 与是否为条件分支标记。
			if (upd_en && upd_br_inst) begin
				btb_valid[upd_btb_idx]   <= 1'b1;
				btb_tag[upd_btb_idx]     <= upd_tag;
				btb_target[upd_btb_idx]  <= upd_br_target;
				btb_is_cond[upd_btb_idx] <= upd_cond_br_inst;
			end

			// 如果是条件跳转且有 update，要更新 BHT 的两位饱和计数器状态，
			// 采用简单的 2-bit 饱和计数器：00 strong not-taken -> 11 strong taken
			if (upd_en && upd_br_inst && upd_cond_br_inst) begin
				case ({upd_br_taken, bht[upd_bht_idx]})
					{1'b1, 2'b00}: bht[upd_bht_idx] <= 2'b01;
					{1'b1, 2'b01}: bht[upd_bht_idx] <= 2'b10;
					{1'b1, 2'b10}: bht[upd_bht_idx] <= 2'b11;
					{1'b1, 2'b11}: bht[upd_bht_idx] <= 2'b11;
					{1'b0, 2'b00}: bht[upd_bht_idx] <= 2'b00;
					{1'b0, 2'b01}: bht[upd_bht_idx] <= 2'b00;
					{1'b0, 2'b10}: bht[upd_bht_idx] <= 2'b01;
					{1'b0, 2'b11}: bht[upd_bht_idx] <= 2'b10;
					default:       bht[upd_bht_idx] <= 2'b01;
				endcase
			end
		end
	end

endmodule
