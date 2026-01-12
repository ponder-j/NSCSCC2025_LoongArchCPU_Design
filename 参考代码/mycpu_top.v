`timescale 1ns / 1ps

module mycpu_top(
    input  wire        clk              ,
    input  wire        resetn           ,
    // inst sram interface
    output wire        inst_sram_req    ,
    output wire        inst_sram_wr     ,
    output wire [ 1:0] inst_sram_size   ,
    output wire [ 3:0] inst_sram_wstrb  ,
    output wire [31:0] inst_sram_addr   ,
    output wire [31:0] inst_sram_wdata  ,
    input  wire        inst_sram_addr_ok,
    input  wire        inst_sram_data_ok,
    input  wire [31:0] inst_sram_rdata  ,
    // data sram interface
    output wire        data_sram_req    ,
    output wire        data_sram_wr     ,
    output wire [ 1:0] data_sram_size   ,
    output wire [ 3:0] data_sram_wstrb  ,
    output wire [31:0] data_sram_addr   ,
    output wire [31:0] data_sram_wdata  ,
    input  wire        data_sram_addr_ok,
    input  wire        data_sram_data_ok,
    input  wire [31:0] data_sram_rdata  ,
    // trace debug interface
    output wire [31:0] debug_wb_pc      ,
    output wire [ 3:0] debug_wb_rf_we   ,
    output wire [ 4:0] debug_wb_rf_wnum ,
    output wire [31:0] debug_wb_rf_wdata
);

    wire        core_inst_en;
    wire [31:0] core_inst_addr;
    wire [31:0] core_inst_rdata;

    wire        core_data_en;
    wire [ 3:0] core_data_wen;
    wire [31:0] core_data_addr;
    wire [31:0] core_data_wdata;
    wire [31:0] core_data_rdata;
    wire [ 1:0] core_data_size;

    wire [31:0] core_debug_wb_pc;
    wire        core_debug_wb_rf_wen;
    wire [ 4:0] core_debug_wb_rf_wnum;
    wire [31:0] core_debug_wb_rf_wdata;

    reg inst_addr_handshaked;
    reg inst_data_valid;
    reg [31:0] inst_rdata_save;

    reg data_addr_handshaked;
    reg data_data_valid;
    reg [31:0] data_rdata_save;

    wire stall_inst;
    wire stall_data;
    wire cpu_ce;
    wire cpu_clk;

    // Stall if core requests but handshake/data not complete
    // For reads: wait for data_valid
    // For writes: also wait for data_valid (which means write complete in this protocol)
    assign stall_inst = core_inst_en && !inst_data_valid;
    assign stall_data = core_data_en && !data_data_valid;
    assign cpu_ce = !resetn || !(stall_inst | stall_data);

    `ifdef SYNTHESIS
    BUFGCE u_cpu_clk_bufgce(
        .I (clk),
        .CE(cpu_ce),
        .O (cpu_clk)
    );
    // In synthesis, BUFGCE guarantees glitch-free gating; when cpu_ce is asserted,
    // the core observes a clean clock edge and advances.
    wire core_adv_en = cpu_ce;
    `else
    // In simulation, directly AND-gating the clock can create glitches/runt pulses when
    // cpu_ce changes near the clk edge, causing the core to advance unexpectedly.
    // Use a negedge-latched enable so cpu_ce is stable during the high phase of clk.
    reg cpu_ce_latched;
    always @(negedge clk or negedge resetn) begin
        if (!resetn) begin
            cpu_ce_latched <= 1'b1;
        end else begin
            cpu_ce_latched <= cpu_ce;
        end
    end
    assign cpu_clk = clk & cpu_ce_latched;
    wire core_adv_en = cpu_ce_latched;
    `endif

    // ----------------------
    // Inst SRAM Interface
    // ----------------------
    // Assert REQ if enable and not yet address-handshaked
    assign inst_sram_req   = core_inst_en && !inst_addr_handshaked && resetn;
    assign inst_sram_wr    = 1'b0;
    assign inst_sram_size  = 2'b10;
    assign inst_sram_wstrb = 4'b0000;
    assign inst_sram_addr  = core_inst_addr;
    assign inst_sram_wdata = 32'b0;

    assign core_inst_rdata = inst_rdata_save;

    always @(posedge clk) begin
        if (!resetn) begin
            inst_addr_handshaked <= 1'b0;
            inst_data_valid      <= 1'b0;
            inst_rdata_save      <= 32'b0;
        end else begin
            // Address Handshake
            if (core_inst_en && inst_sram_req && inst_sram_addr_ok) begin
                inst_addr_handshaked <= 1'b1;
            end

            // Data Handshake
            if (core_inst_en && inst_sram_data_ok) begin
                inst_rdata_save <= inst_sram_rdata;
                inst_data_valid <= 1'b1;
            end

            // Clear flags only when the core actually advances.
            // Use a stable enable (core_adv_en) to avoid races/glitches.
            if (core_adv_en && core_inst_en && inst_data_valid) begin
                inst_addr_handshaked <= 1'b0;
                inst_data_valid      <= 1'b0;
            end
        end
    end

    // ----------------------
    // Data SRAM Interface
    // ----------------------
    assign data_sram_req   = core_data_en && !data_addr_handshaked && resetn;
    assign data_sram_wr    = |core_data_wen;
    assign data_sram_size  = core_data_size;
    assign data_sram_wstrb = core_data_wen;
    assign data_sram_addr  = core_data_addr;
    assign data_sram_wdata = core_data_wdata;

    assign core_data_rdata = data_rdata_save;

    always @(posedge clk) begin
        if (!resetn) begin
            data_addr_handshaked <= 1'b0;
            data_data_valid      <= 1'b0;
            data_rdata_save      <= 32'b0;
        end else begin
            if (core_data_en && data_sram_req && data_sram_addr_ok) begin
                data_addr_handshaked <= 1'b1;
            end

            if (core_data_en && data_sram_data_ok) begin
                data_rdata_save <= data_sram_rdata;
                data_data_valid <= 1'b1;
            end

            if (core_adv_en && core_data_en && data_data_valid) begin
                data_addr_handshaked <= 1'b0;
                data_data_valid      <= 1'b0;
            end
        end
    end

    // ----------------------
    // Core Instantiation
    // ----------------------
    cpu u_cpu(
        .clk            (cpu_clk),
        .resetn         (resetn),

        .inst_sram_en    (core_inst_en),
        .inst_sram_addr  (core_inst_addr),
        .inst_sram_rdata (core_inst_rdata),

        .data_sram_en    (core_data_en),
        .data_sram_wen   (core_data_wen),
        .data_sram_addr  (core_data_addr),
        .data_sram_wdata (core_data_wdata),
        .data_sram_rdata (core_data_rdata),
        .data_sram_size  (core_data_size),

        .debug_wb_pc      (core_debug_wb_pc),
        .debug_wb_rf_wen  (core_debug_wb_rf_wen),
        .debug_wb_rf_wnum (core_debug_wb_rf_wnum),
        .debug_wb_rf_wdata(core_debug_wb_rf_wdata)
    );

    assign debug_wb_pc       = core_debug_wb_pc;
    assign debug_wb_rf_we    = {4{core_debug_wb_rf_wen}};
    assign debug_wb_rf_wnum  = core_debug_wb_rf_wnum;
    assign debug_wb_rf_wdata = core_debug_wb_rf_wdata;

endmodule
