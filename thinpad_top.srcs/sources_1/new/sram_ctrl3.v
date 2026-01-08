`timescale 1ns / 1ps

module sram_ctrl3 (
    clk,
    start_operation,
    rw,
    address_input,
    data_f2s,
    data_s2f,
    wstrb,

    address_to_sram_output,
    we_to_sram_output,
    oe_to_sram_output,
    ce_to_sram_output,
    be_to_sram_output,
    data_from_to_sram_input_output,

    data_ready_signal_output,
    writing_finished_signal_output,
    busy_signal_output
  );

  input wire clk;  // Clock signal
  input wire start_operation;  // Start operation signal

  input wire rw;  // Read/Write signal
  input wire [ 3:0] wstrb;  // Write strobe signal
  input wire [19:0] address_input;  // Address input
  input wire [31:0] data_f2s;  // Data from FPGA to SRAM

  output wire [31:0] data_s2f;  // Data from SRAM to FPGA
  output reg [19:0] address_to_sram_output;  // Address to SRAM

  output reg we_to_sram_output;  // Write enable to SRAM (active low)
  output reg oe_to_sram_output;  // Output enable to SRAM (active low)
  output reg ce_to_sram_output;  // Chip enable to SRAM (active low)
  output reg [3:0] be_to_sram_output;  // Byte enable to SRAM (active low)

  inout wire [31:0] data_from_to_sram_input_output;  // Data from/to SRAM

  output reg data_ready_signal_output;  // Data ready signal
  output reg writing_finished_signal_output;  // Writing finished signal
  output reg busy_signal_output;  // Busy signal

  // FSM states declaration
  localparam [3:0]
             Rd0 = 4'b0000,
             Rd1 = 4'b0001,
             Rd2 = 4'b0010,
             Rd3 = 4'b0011,
             Wr0 = 4'b0100,
             Wr1 = 4'b0101,
             Wr2 = 4'b0110,
             Wr3 = 4'b0111,
             Idle = 4'b1000;

  // signals declaration
  reg [3:0] state_reg;

  reg [31:0] register_for_reading_data;
  reg [31:0] register_for_writing_data;

  reg register_for_splitting;

  reg [19:0] buffer_address;
  reg [31:0] buffer_wdata;
  reg [3:0] buffer_wstrb;


  initial
  begin
    ce_to_sram_output = 1'b1;
    oe_to_sram_output = 1'b1;
    we_to_sram_output = 1'b1;

    state_reg = Idle;

    register_for_reading_data[31:0] = 0;
    register_for_writing_data[31:0] = 0;

    register_for_splitting = 1'b0;

    data_ready_signal_output = 1'b0;
    writing_finished_signal_output = 1'b0;
    busy_signal_output = 1'b0;

    buffer_address = 0;
    buffer_wdata = 0;
    buffer_wstrb = 0;
  end

  always @(posedge clk)
  begin
    case (state_reg)
      Idle:
      begin
        if (~start_operation)
          state_reg <= Idle;
        else
        begin
          buffer_address <= address_input;
          buffer_wdata <= data_f2s;
          buffer_wstrb <= wstrb;
          if (rw)
            state_reg <= Rd0;
          else
            state_reg <= Wr0;
        end
      end

      Rd0:
      begin
        busy_signal_output <= 1'b1;
        address_to_sram_output[19:0] <= buffer_address[19:0];
        state_reg <= Rd1;
      end

      Rd1:
      begin
        ce_to_sram_output <= 1'b0;
        oe_to_sram_output <= 1'b0;
        we_to_sram_output <= 1'b1;
        be_to_sram_output <= 4'h0;
        state_reg <= Rd2;
      end

      Rd2:
      begin
        register_for_reading_data[31:0] <= data_from_to_sram_input_output[31:0];
        data_ready_signal_output <= 1'b1;

        state_reg <= Rd3;
      end

      Rd3:
      begin
        ce_to_sram_output <= 1'b1;
        oe_to_sram_output <= 1'b1;
        we_to_sram_output <= 1'b1;

        busy_signal_output <= 1'b0;

        data_ready_signal_output <= 1'b0;

        state_reg <= Idle;
      end

      Wr0:
      begin
        busy_signal_output <= 1'b1;

        address_to_sram_output[19:0] <= buffer_address[19:0];
        register_for_writing_data[31:0] <= buffer_wdata[31:0];

        state_reg <= Wr1;
      end

      Wr1:
      begin
        ce_to_sram_output <= 1'b0;
        oe_to_sram_output <= 1'b1;
        we_to_sram_output <= 1'b0;
        be_to_sram_output <= ~buffer_wstrb[3:0];
        register_for_splitting <= 1'b1;

        state_reg <= Wr2;

      end

      Wr2:
      begin

        ce_to_sram_output <= 1'b1;
        oe_to_sram_output <= 1'b1;
        we_to_sram_output <= 1'b1;
     
        writing_finished_signal_output <= 1'b1;

        state_reg <= Wr3;
      end

      Wr3:
      begin

        busy_signal_output <= 1'b0;

        register_for_splitting <= 1'b0;

        writing_finished_signal_output <= 1'b0;

        state_reg <= Idle;
      end
    endcase
  end

  assign data_s2f = register_for_reading_data[31:0];

  assign data_from_to_sram_input_output[31:0] = register_for_splitting ?
         register_for_writing_data[31:0] : 32'hZZZZ_ZZZZ;
endmodule
