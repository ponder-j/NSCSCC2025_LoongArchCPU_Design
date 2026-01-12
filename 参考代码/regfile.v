module regfile(
    input clk,
    input reset,
    input [4:0] raddr1,
    input [4:0] raddr2,
    output [31:0] rdata1,
    output [31:0] rdata2,
    input we,
    input [4:0] waddr,
    input [31:0] wdata
);
    reg [31:0] regs[31:0];  // 32个32位通用寄存器
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'b0;
            end
        end else if (we && (waddr != 5'b00000)) begin  // r0恒为0，不能被写入
            regs[waddr] <= wdata;
        end
    end
    
    assign rdata1 = (raddr1==5'b0) ? 32'b0 : regs[raddr1];
    assign rdata2 = (raddr2==5'b0) ? 32'b0 : regs[raddr2];

endmodule
