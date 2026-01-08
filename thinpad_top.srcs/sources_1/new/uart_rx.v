//
// Set Parametere CLKS_PER_BIT as follows:
//  CLKS_PER_BIT = (Frequency of clock) / (Frequency of UART)
//     Example: 10 MHz Clock, 115200 baud UART
//              10000000/115200 = 87
//     Example: 50 MHz Clock, 9600 baud UART
//              50000000/9600 = 5208

module uart_rx #(
    parameter [12:0] CLKS_PER_BIT = 5208
) (
    input wire clock,
    input wire i_rx,
    output wire o_data_avail,
    output wire [7:0] o_data_byte
);

  localparam [1:0] IDLE_STATE = 2'b00;
  localparam [1:0] START_STATE = 2'b01;
  localparam [1:0] GET_BIT_STATE = 2'b10;
  localparam [1:0] STOP_STATE = 2'b11;

  reg        rx_buffer = 1'b1;
  reg        rx = 1'b1;

  reg [ 1:0] state = 0;
  reg [12:0] counter = 0;
  reg [ 2:0] bit_index = 0;  // where to place the next bit (0...7)
  reg        data_avail = 0;
  reg [ 7:0] data_byte = 0;

  assign o_data_avail = data_avail;
  assign o_data_byte  = data_byte;

  // Double-buffer the incoming Rx line. This allows it to be
  // used in the UART RX Clock Domain and removes problems cased
  // by metastability.

  always @(posedge clock) begin
    rx_buffer <= i_rx;
    rx        <= rx_buffer;
  end
  //The state machine
  always @(posedge clock) begin
    case (state)
      IDLE_STATE: begin
        data_avail <= 0;
        counter <= 0;
        bit_index <= 0;
        if (rx == 0)  // Start bit detected
          state <= START_STATE;
        else state <= IDLE_STATE;
      end

      // Wait until the middle of the start bit
      START_STATE: begin
        if (counter == (CLKS_PER_BIT - 1) / 2) begin
          if (rx == 0) // If still low at the
          begin
            counter <= 0;
            state   <= GET_BIT_STATE;
          end else begin
            state <= IDLE_STATE;
          end
        end else begin
          counter <= counter + 1;
          state   <= START_STATE;
        end
      end

      // Wait CLKS_PER_BIT-1 clock cycles to sample RX for next bit
      GET_BIT_STATE: begin
        if (counter < CLKS_PER_BIT - 1) begin
          counter <= counter + 1;
          state   <= GET_BIT_STATE;
        end else begin
          counter <= 0;
          data_byte[bit_index] <= rx;

          // Check if we have received all bits
          if (bit_index < 7) begin
            bit_index <= bit_index + 3'b001;
            state <= GET_BIT_STATE;
          end else begin
            bit_index <= 0;
            state <= STOP_STATE;
          end
        end
      end

      // Wait until this middle of the stop bit
      STOP_STATE: begin
        if (counter < CLKS_PER_BIT - 1) begin
          counter <= counter + 1;
          state   <= STOP_STATE;
        end else begin
          data_avail <= 1;
          counter <= 0;
          state <= IDLE_STATE;
        end
      end

      default: state <= IDLE_STATE;
    endcase
  end
endmodule
