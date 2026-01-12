`include "cpu.vh"

module alu_(
    input [31:0] op1,       // 操作数1 (rdata1)
    input [31:0] op2,       // 操作数2 (rdata2 或 立即数)
    input [3:0] alu_op,     // ALU 操作码
    output reg [31:0] alu_output // ALU 计算结果
);

always @(*) begin
    alu_output = 32'h0000_0000;
    case (alu_op)
        `ALU_ADD:  alu_output = op1 + op2;
        `ALU_SUB:  alu_output = op1 - op2;
        `ALU_SLT:  alu_output = ($signed(op1) < $signed(op2)) ? 32'h0000_0001 : 32'h0000_0000;
        `ALU_AND:  alu_output = op1 & op2;
        `ALU_OR:   alu_output = op1 | op2;
        `ALU_XOR:  alu_output = op1 ^ op2;
        `ALU_SLL:  alu_output = op1 << (op2[4:0]); // 逻辑左移：取 op2 低5位作为移位量
        `ALU_SRL:  alu_output = op1 >> (op2[4:0]); // 逻辑右移
        `ALU_MUL:  alu_output = $signed(op1) * $signed(op2); // 有符号乘法
        `ALU_OP2:  alu_output = op2; // 直接输出 op2 (for lu12i.w)
        default:  alu_output = 32'h0000_0000;
    endcase
end

endmodule
