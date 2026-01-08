module uart (
    input wire i_uart_req,
    input wire i_uart_addr,
    input wire i_uart_wr,
    input wire [7:0] i_uart_wdata,

    output reg [7:0] o_uart_rdata,
    output reg       o_uart_data_ok,

    input wire clk,
    input wire reset,

    input wire rxd,
    output wire txd

);

// 写0xBFD003F8时即（0），写数据的低8位送给串口发送逻辑，出发串口发送操作
// 读0xBFD003F8时即（0），读串口接收逻辑接收到的数据，同时清除串口接收逻辑的数据有效标志

wire [7:0] address_1_data = {6'b0, reg_tx_data_avail, !tx_active};


// if (!wr && address == 0) begin
//     uart_rdata <= reg_tx_data_byte;
//     if (rx_data_avail) begin
//         reg_tx_data_byte <= rx_data_byte;
//         reg_tx_data_avail <= 1;
//     end else begin
//         reg_tx_data_avail <= 0;
//     end
// end else if (rx_data_avail) begin
//     reg_tx_data_byte <= rx_data_byte;
//     reg_tx_data_avail <= 1;
// end 

reg [1:0] state;
localparam [1:0] Idle = 2'b00;
localparam [1:0] Rd0 = 2'b01;
localparam [1:0] Wr0 = 2'b10;

initial begin
    state = Idle;
    o_uart_data_ok = 0;
    reg_tx_data_byte = 8'b0;
    reg_tx_data_avail = 1'b0;
end

always @(posedge clk) begin
    if (reset) begin
        // tx_data_byte <= 8'b0;
        // tx_data_avail <= 1'b0;
        state <= Idle;
        o_uart_data_ok <= 0;
        o_uart_rdata <= 8'b0;
    end else begin
        case (state)
        Idle:
        begin
            if (!i_uart_req) begin
                o_uart_data_ok <= 0;
                o_uart_rdata <= 8'b0;
                state <= Idle;
            end else begin // i_uart_req
                if (i_uart_wr) begin // 写
                    if (i_uart_addr == 1) begin
                        o_uart_data_ok <= 1;
                        state <= Idle;
                    end else  begin // i_uart_req && i_uart_wr && i_uart_addr == 0
                        state <= Wr0;
                    end
                end else begin // !i_uart_wr 读
                    if (i_uart_addr == 1) begin
                        o_uart_data_ok <= 1;
                        o_uart_rdata <= address_1_data;
                        // o_uart_rdata <= reg_tx_data_byte;
                        state <= Idle;
                    end else begin // i_uart_req && !i_uart_wr && i_uart_addr == 0
                        o_uart_data_ok <= 1;
                        o_uart_rdata <= reg_tx_data_byte;
                        state <= Idle;
                    end
                end
            end
        end


        Wr0:
        begin
            // if (i_uart_addr == 1) begin
            //     o_uart_data_ok <= 1;
            //     state <= Idle;
            // end else if (i_uart_addr == 0) begin
            //     uart_rdata <= wdata;
            //     uart_data_ok <= 1;
            //     state <= Idle;
            // end
            if (uart_write_done) begin
                o_uart_data_ok <= 1;
                state <= Idle;
            end else begin
                state <= Wr0;
            end
        end
        endcase
    end
end;

uart_tx tx (
    .clock(clk),
    .i_data_avail(i_uart_req && i_uart_wr && i_uart_addr == 0),
    .i_data_byte(i_uart_wdata),
    .o_active(tx_active),
    .o_tx(txd),
    .o_done(uart_write_done)
);
wire tx_active;
wire uart_write_done;


uart_rx rx (
    .clock(clk),
    .i_rx(rxd),
    .o_data_avail(rx_data_avail),
    .o_data_byte(rx_data_byte)
);

wire [7:0] rx_data_byte;
wire rx_data_avail;

reg [7:0] reg_tx_data_byte;
reg reg_tx_data_avail;

always @(posedge clk) begin
    if (reset) begin
        reg_tx_data_byte <= 8'b0;
        reg_tx_data_avail <= 1'b0;
    end else begin
        if (i_uart_req && !i_uart_wr && i_uart_addr == 0) begin
            if (rx_data_avail) begin
                reg_tx_data_byte <= rx_data_byte;
                reg_tx_data_avail <= 1'b1;
            end else begin
                reg_tx_data_avail <= 1'b0;
            end
        end else if (rx_data_avail) begin
            reg_tx_data_avail <= 1'b1;
            reg_tx_data_byte <= rx_data_byte;
        end
    end
end

endmodule
