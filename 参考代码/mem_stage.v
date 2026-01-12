`include "cpu.vh"

module mem_stage(
    input clk, reset,

    // 握手信号
    output mem_allow_in,
    input exe_to_mem_valid,
    input wb_allow_in,
    output mem_to_wb_valid,

    input [`EXE_TO_MEM_BUS_WIDTH-1:0] exe_to_mem_bus,
    output [`MEM_TO_WB_BUS_WIDTH-1:0] mem_to_wb_bus,

    // 冲突检测
    output [`MEM_TO_ID_BUS_WIDTH-1:0] mem_to_id_bus,

    // CPU 接口
    input[31:0]     data_sram_rdata
);

    reg [`EXE_TO_MEM_BUS_WIDTH-1:0] mem_reg;
    wire [31:0] pc;
    wire [22:0] inst_decode;
    wire [31:0] alu_output;
    wire [4:0] rd;
    assign {
        pc,
        inst_decode,
        alu_output,
        rd
    } = mem_reg;

    wire mem_rf_wen;
    wire [4:0] mem_rf_waddr;
    wire [31:0] mem_rf_wdata;

    reg [31:0] load_data_r;

    assign mem_to_wb_bus = {
        pc,
        mem_rf_wen,
        mem_rf_waddr,
        mem_rf_wdata
    };

    reg  mem_valid;

    // Instructions that write to RF:
    // ADD_W, SUB_W, AND, MUL_W, SLLI_W, SLTI, ADDI_W, ORI
    // LD_W, LD_B
    // LU12I_W, PCADDU12I
    // OR, ANDI, XOR, SRLI_W
    // JIRL, BL
    assign mem_rf_wen = (mem_valid) && (rd != 0) &&
        (inst_decode[`IDX_ADD_W]  || inst_decode[`IDX_SUB_W]  || inst_decode[`IDX_AND]    || inst_decode[`IDX_MUL_W]  ||
         inst_decode[`IDX_SLLI_W] || inst_decode[`IDX_SLTI]   || inst_decode[`IDX_ADDI_W] || inst_decode[`IDX_ORI]    ||
         inst_decode[`IDX_LD_W]   || inst_decode[`IDX_LD_B]   ||
         inst_decode[`IDX_LU12I_W]|| inst_decode[`IDX_PCADDU12I]||
         inst_decode[`IDX_OR]     || inst_decode[`IDX_ANDI]   || inst_decode[`IDX_XOR]    || inst_decode[`IDX_SRLI_W] ||
         inst_decode[`IDX_JIRL]   || inst_decode[`IDX_BL]);

    assign mem_rf_waddr = (inst_decode[`IDX_BL]) ? 5'd1 : rd; // Handle BL writing to r1 here as well if passed rd was wrong, but better to trust upstream if fixed. Upstream EXE didn't fix 'rd' in bus, but fixed 'exe_rd' for hazard. 'rd' comes from ID->EXE->MEM. 
    // In ID stage, 'rd' is inst[4:0]; for BL, inst[4:0] is part of offset. Wait!
    // BL encoding: 31:26 opcode, 25:0 offset.
    // So inst[4:0] is part of offset. It is NOT valid rd.
    // So 'rd' passed down the pipeline for BL is garbage.
    // I MUST override it to 1.
    
    // LD_B logic
    wire [7:0] byte_val;
    // Assume data_sram_rdata contains word.
    // alu_output is the address.
    assign byte_val = load_data_r >> (alu_output[1:0] * 8);
    wire [31:0] ld_b_result;
    assign ld_b_result = {{24{byte_val[7]}}, byte_val};

    assign mem_rf_wdata = 
        (inst_decode[`IDX_LD_W]) ? load_data_r : 
        (inst_decode[`IDX_LD_B]) ? ld_b_result :
        alu_output;

    wire [4:0] mem_rd;
    wire mem_write;
    wire [31:0] mem_wdata;
    assign mem_rd = mem_rf_waddr;
    assign mem_write = mem_rf_wen;
    assign mem_wdata = mem_rf_wdata;
    assign mem_to_id_bus = {mem_rd, mem_write, mem_wdata};

    wire mem_ready_go;
    assign mem_ready_go = 1;
    assign mem_allow_in = !mem_valid || (mem_ready_go && wb_allow_in);
    assign mem_to_wb_valid = mem_valid && mem_ready_go;

    always @(posedge clk) begin
        if (reset) begin
            mem_valid <= 1'b0;
        end else if (mem_allow_in) begin
            mem_valid <= exe_to_mem_valid;
        end
    end

    always @(posedge clk) begin
        if (mem_allow_in && exe_to_mem_valid) begin
            mem_reg <= exe_to_mem_bus;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            load_data_r <= 32'b0;
        end else if (mem_allow_in && exe_to_mem_valid) begin
            load_data_r <= data_sram_rdata;
        end
    end

endmodule
