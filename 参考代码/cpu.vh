`ifndef CPU_VH
`define CPU_VH

`define IF_TO_ID_BUS_WIDTH 97
`define ID_TO_EXE_BUS_WIDTH 192
`define EXE_TO_MEM_BUS_WIDTH 92
`define MEM_TO_WB_BUS_WIDTH 70
`define ID_TO_IF_BUS_WIDTH 101
`define WB_TO_ID_BUS_WIDTH 38
`define EXE_TO_ID_BUS_WIDTH 39
`define MEM_TO_ID_BUS_WIDTH 38

`define ALU_OP_WIDTH 4
`define ALU_NOP  4'd0
`define ALU_ADD  4'd1
`define ALU_SUB  4'd2
`define ALU_SLT  4'd3
`define ALU_AND  4'd4
`define ALU_OR   4'd5
`define ALU_SLL  4'd6
`define ALU_MUL  4'd7
// New ALU Ops
`define ALU_XOR  4'd8
`define ALU_SRL  4'd9
`define ALU_OP2  4'd10 // For lu12i.w, output = op2

`define OP_ADD_W      17'b0000_0000_0001_00000
`define OP_SUB_W      17'b0000_0000_0001_00010
`define OP_AND        17'b0000_0000_0001_01001
`define OP_OR         17'b0000_0000_0001_01010
`define OP_XOR        17'b0000_0000_0001_01011
`define OP_MUL_W      17'b0000_0000_0001_11000
`define OP_SLLI_W     17'b0000_0000_0100_00001
`define OP_SRLI_W     17'b0000_0000_0100_01001

`define OP_SLTI       10'b0000_001000
`define OP_ADDI_W     10'b0000_001010
`define OP_ANDI       10'b0000_001101
`define OP_ORI        10'b0000_001110
`define OP_LD_W       10'b0010_100010
`define OP_ST_W       10'b0010_100110
`define OP_LD_B       10'b0010_100000
`define OP_ST_B       10'b0010_100100

`define OP_B          6'b010100
`define OP_BL         6'b010101
`define OP_BEQ        6'b010110
`define OP_BNE        6'b010111
`define OP_JIRL       6'b010011

`define OP_LU12I_W    7'b0001010
`define OP_PCADDU12I  7'b0001110

// 指令索引定义 - Total 23 instructions
`define IDX_ADD_W     0
`define IDX_SUB_W     1
`define IDX_AND       2
`define IDX_MUL_W     3
`define IDX_SLLI_W    4
`define IDX_SLTI      5
`define IDX_ADDI_W    6
`define IDX_ORI       7
`define IDX_LD_W      8
`define IDX_ST_W      9
`define IDX_B         10
`define IDX_BEQ       11

`define IDX_LU12I_W   12
`define IDX_PCADDU12I 13
`define IDX_OR        14
`define IDX_ANDI      15
`define IDX_XOR       16
`define IDX_SRLI_W    17
`define IDX_JIRL      18
`define IDX_BNE       19
`define IDX_BL        20
`define IDX_ST_B      21
`define IDX_LD_B      22


`endif
