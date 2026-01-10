`include "mycpu_top.h"

module exe_stage (
    input clk,
    input reset,

    // pipeline control
    output exe_allow_in,
    input  id_to_exe_valid,
    input  mem_allow_in,
    output exe_to_mem_valid,

    // bus from id
    input [`ID_TO_EXE_BUS_WIDTH-1:0] id_to_exe_bus,

    // bus to mem
    output [`EXE_TO_MEM_BUS_WIDTH-1:0] exe_to_mem_bus,

    // bus to id (for hazard detect)
    output [`EXE_TO_ID_BUS_WIDTH-1:0] exe_to_id_bus,

    // data sram interface
    output wire        data_sram_req    ,  // 数据存储器请求信号，为1时表示本次请求有效，为0时表示无效
    output wire        data_sram_wr     ,  // 数据存储器写信号，为1表示该次是写请求，为0为读请求
    output wire [ 1:0] data_sram_size   ,  // 数据存储器传输字节数，2’b00对应1字节，2’b01对应2字节，2’b10对应4字节
    output wire [ 3:0] data_sram_wstrb  ,  // 数据存储器字节写使能
    output wire [31:0] data_sram_addr   ,  // 数据存储器请求的地址
    output wire [31:0] data_sram_wdata  ,  // 数据存储器写数据
    input  wire        data_sram_addr_ok,  // 数据存储器地址握手信号，读请求表示本次传输地址被接收，写请求表示本次传输地址和数据被接收
    input  wire        data_sram_data_ok,  // 数据存储器数据有效信号，读请求表示返回数据有效，写请求表示数据写入完成
    input  wire [31:0] data_sram_rdata     // 数据存储器读数据
);

    reg [`ID_TO_EXE_BUS_WIDTH-1:0] exe_reg;
    wire [31:0] exe_pc;
    wire [31:0] exe_rj_value;
    wire [31:0] exe_rkd_value;
    wire [31:0] exe_imm;
    wire [11:0] exe_alu_op;
    wire        exe_src1_is_pc;
    wire        exe_src2_is_imm;
    wire        exe_res_from_mem;
    wire        exe_reg_we;
    wire        exe_mem_en;
    wire [3:0]  exe_mem_we;
    wire [4:0]  exe_reg_waddr;

    assign {
        exe_pc,
        exe_rj_value,
        exe_rkd_value,
        exe_imm,
        exe_alu_op,
        exe_src1_is_pc,
        exe_src2_is_imm,
        exe_res_from_mem,
        exe_reg_we,
        exe_mem_en,
        exe_mem_we,
        exe_reg_waddr
    } = exe_reg;

    // output bus to MEM
    wire [31:0] alu_result;
    assign exe_to_mem_bus = {
        exe_pc,           // 32 bits
        exe_rkd_value,    // 32 bits
        alu_result,       // 32 bits
        exe_res_from_mem, // 1 bit
        exe_reg_we,       // 1 bit
        exe_mem_en,       // 1 bit
        exe_mem_we,       // 4 bits
        exe_reg_waddr     // 5 bits
    };

    assign exe_to_id_bus = {exe_valid, exe_reg_we, exe_reg_waddr, alu_result, exe_res_from_mem};

    // 请求完成标志位
    reg data_sram_req_done; 

    always @(posedge clk) begin
        if (reset) begin
            data_sram_req_done <= 1'b0;
        end else if (exe_ready_go && mem_allow_in) begin
            // 当指令流向下一级时，清除标志位，为下一条指令做准备
            data_sram_req_done <= 1'b0;
        end else if (data_sram_req && data_sram_addr_ok) begin
            // 当握手成功，标记为已完成
            data_sram_req_done <= 1'b1;
        end
    end

    // EXE级有效 且 是访存指令 且 还没握手成功
    assign data_sram_req = exe_valid && exe_mem_en && !data_sram_req_done;
    // 1 表示写 (Store), 0 表示读 (Load)
    assign data_sram_wr    = |exe_mem_we;
    // 4 字节
    assign data_sram_size  = 2'b10;
    // addr: ALU 计算结果
    assign data_sram_addr  = alu_result;
    // wdata: 待写入数据
    // 潜在问题（AI说的，先留着）： 如果这是一条 SB (Store Byte) 指令，exe_rkd_value 是寄存器的原始值（比如 0x12345678），而地址是 0x1。
    // 标准的 SRAM 接口通常要求：如果你要写到第 1 字节，数据必须已经在 wdata[15:8] 上。
    // 也就是说，Store 的数据通常需要根据地址的低 2 位进行移位（Alignment）。
    // 检查点： 请确认你的 ID 阶段 生成 exe_rkd_value 时，或者在 EXE 阶段，是否已经处理了“Store 数据的移位”？
    assign data_sram_wdata = exe_rkd_value;

    // pipeline control
    reg  exe_valid;
    wire exe_ready_go;

    // 如果是访存指令 (exe_mem_en)，必须等到握手成功 (addr_ok 为高 OR 之前已经 done)
    // 如果是非访存指令，直接 Ready
    assign exe_ready_go = !exe_mem_en || (data_sram_req && data_sram_addr_ok) || data_sram_req_done;
    assign exe_allow_in = !exe_valid || exe_ready_go && mem_allow_in;
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

    // internal signals
    wire [11:0] alu_op;
    wire [31:0] alu_src1;
    wire [31:0] alu_src2;
    // wire [31:0] alu_result;

    // EXE stage
    assign alu_op    = exe_alu_op;
    assign alu_src1  = exe_src1_is_pc ? exe_pc : exe_rj_value;
    assign alu_src2  = exe_src2_is_imm ? exe_imm : exe_rkd_value;

    myalu u_alu (
        .alu_op    (alu_op),
        .alu_src1  (alu_src1),
        .alu_src2  (alu_src2),
        .alu_result(alu_result)
    );

endmodule

