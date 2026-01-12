`include "cpu.vh"

module cpu(
    input           clk,                // 时钟信号
    input           resetn,             // 低有效复位信号

    output          inst_sram_en,       // 指令存储器使能
    output[31:0]    inst_sram_addr,     // 指令存储器读地址
    input[31:0]     inst_sram_rdata,    // 指令存储器读数据

    output          data_sram_en,       // 数据存储器端口读/写使能
    output[3:0]     data_sram_wen,      // 数据存储器写使能      
    output[31:0]    data_sram_addr,     // 数据存储器读/写地址
    output[31:0]    data_sram_wdata,    // 写入数据存储器的数据
    output[1:0]     data_sram_size,     // 数据存储器访问大小
    input[31:0]     data_sram_rdata,    // 数据存储器读出数据

    // 供自动测试机使用的CPU正确性校验接口
    output[31:0]    debug_wb_pc,        // 当前正在执行指令的PC
    output          debug_wb_rf_wen,    // 当前通用寄存器组写使能信号
    output[4:0]     debug_wb_rf_wnum,   // 当前通用寄存器组写回的寄存器号
    output[31:0]    debug_wb_rf_wdata   // 当前指令需要写回的数据
);

    reg reset;
    always @(posedge clk) reset <= ~resetn;

    // IF
    wire if_to_id_valid;
    wire [`IF_TO_ID_BUS_WIDTH-1:0] if_to_id_bus;

    // ID
    wire id_allow_in;
    wire id_to_exe_valid;
    wire [`ID_TO_EXE_BUS_WIDTH-1:0] id_to_exe_bus;
    wire [`ID_TO_IF_BUS_WIDTH-1:0] id_to_if_bus;

    // EXE
    wire exe_allow_in;
    wire exe_to_mem_valid;
    wire [`EXE_TO_MEM_BUS_WIDTH-1:0] exe_to_mem_bus;
    wire [`EXE_TO_ID_BUS_WIDTH-1:0] exe_to_id_bus;

    // MEM
    wire mem_allow_in;
    wire mem_to_wb_valid;
    wire mem_valid;
    wire [`MEM_TO_WB_BUS_WIDTH-1:0] mem_to_wb_bus;
    wire [`MEM_TO_ID_BUS_WIDTH-1:0] mem_to_id_bus;

    // WB
    wire wb_allow_in;
    wire [`WB_TO_ID_BUS_WIDTH-1:0] wb_to_id_bus;

    if_stage if_stage (
        .clk(clk),
        .reset(reset),
        .id_allow_in(id_allow_in),
        .if_to_id_valid(if_to_id_valid),
        .if_to_id_bus(if_to_id_bus),
        .id_to_if_bus(id_to_if_bus),
        .inst_sram_en(inst_sram_en),
        .inst_sram_addr(inst_sram_addr),
        .inst_sram_rdata(inst_sram_rdata)
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
        .id_to_if_bus(id_to_if_bus),
        .wb_to_id_bus(wb_to_id_bus),
        .exe_to_id_bus(exe_to_id_bus),
        .mem_to_id_bus(mem_to_id_bus)
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
        .data_sram_wen(data_sram_wen),
        .data_sram_addr(data_sram_addr),
        .data_sram_wdata(data_sram_wdata),
        .data_sram_size(data_sram_size)
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
        .debug_wb_rf_wen(debug_wb_rf_wen),
        .debug_wb_rf_wnum(debug_wb_rf_wnum),
        .debug_wb_rf_wdata(debug_wb_rf_wdata)
    );


endmodule
