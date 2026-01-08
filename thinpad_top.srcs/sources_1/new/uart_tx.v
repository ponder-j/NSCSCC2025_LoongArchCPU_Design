//
// Set Parametere CLKS_PER_BIT as follows:
//  CLKS_PER_BIT = (Frequency of clock) / (Frequency of UART)
//     Example: 10 MHz Clock, 115200 baud UART
//              10000000/115200 = 87
//     Example: 50 MHz Clock, 9600 baud UART
//              50000000/9600 = 5209

module uart_tx #(
    parameter [12:0] CLKS_PER_BIT = 5209
) (
    input wire clock,
    input wire i_data_avail, // If HIGH, start transmission
    input wire [7:0] i_data_byte,
    output reg o_active, // HIGH while busy transmitting
    output reg o_tx,     // Connect this to the Tx line
    output reg o_done     // HIGH for one clock when complete
);

  localparam [1:0] IdleState = 2'b00;
  localparam [1:0] StartState = 2'b01;
  localparam [1:0] SendBitState = 2'b10;
  localparam [1:0] StopState = 2'b11;

  reg [ 1:0] state = 0;
  reg [12:0] counter = 0;
  reg [ 2:0] bit_index = 0;
  reg [ 7:0] data_byte = 0;

  always @(posedge clock) begin
    case (state)
      IdleState: begin
        o_tx      <= 1;
        o_done    <= 0;
        counter   <= 0;
        bit_index <= 0;
        if (i_data_avail == 1) begin
          state <= StartState;
          data_byte <= i_data_byte;
          o_active <= 1;
        end else begin
          state <= IdleState;
          o_active <= 0;
        end
      end

      // Send Start Bit
      StartState: begin
        o_tx <= 0;
        // Wait CLKS_PER_BIT-1 clock cycles for start bit to finish
        if (counter < CLKS_PER_BIT - 1) begin
          counter <= counter + 1;
          state   <= StartState;
        end else begin
          counter <= 0;
          state   <= SendBitState;
        end
      end
      // Wait CLKS_PER_BIT clock cycles for each data bit
      SendBitState: begin
        o_tx <= data_byte[bit_index];
        if (counter < CLKS_PER_BIT - 1) begin
          counter <= counter + 1;
          state   <= SendBitState;
        end else begin
          counter <= 0;
          // Check if we have sent all bits
          if (bit_index < 7) begin
            bit_index <= bit_index + 1;
            state <= SendBitState;
          end else begin
            bit_index <= 0;
            state <= StopState;
          end
        end
      end

      // Send Stop Bit
      StopState: begin
        o_tx <= 1;
        // Wait CLKS_PER_BIT-1 clock cycles for stop bit to finish
        if (counter < CLKS_PER_BIT - 1) begin
          counter <= counter + 1;
          state   <= StopState;
        end else begin
          counter <= 0;
          state   <= IdleState;
          o_done  <= 1;
        end
      end

      default: begin
        o_tx <= 1;
        o_active <= 0;
        counter <= 0;
        bit_index <= 0;
        state <= IdleState;
      end
    endcase
  end

endmodule
