
module likesram_interconnect (
    input  wire        clk,
    input  wire        reset,
    // mycpu bus
    input  wire        inst_sram_req,
    input  wire        inst_sram_wr,
    input  wire [ 1:0] inst_sram_size,     // size 用不到
    input  wire [ 3:0] inst_sram_wstrb,    // inst_sram_wstrb 用不到
    input  wire [31:0] inst_sram_addr,
    input  wire [31:0] inst_sram_wdata,    // inst_sram_wdata 用不到
    output wire        inst_sram_addr_ok,
    output wire        inst_sram_data_ok,
    output wire [31:0] inst_sram_rdata,

    input  wire        data_sram_req,
    input  wire        data_sram_wr,
    input  wire [ 1:0] data_sram_size,
    input  wire [ 3:0] data_sram_wstrb,
    input  wire [31:0] data_sram_addr,
    input  wire [31:0] data_sram_wdata,
    output wire        data_sram_addr_ok,
    output wire        data_sram_data_ok,
    output wire [31:0] data_sram_rdata,

    inout  wire [31:0] base_ram_data,
    output wire [19:0] base_ram_addr,
    output wire [ 3:0] base_ram_be_n,
    output wire        base_ram_ce_n,
    output wire        base_ram_oe_n,
    output wire        base_ram_we_n,

    inout  wire [31:0] ext_ram_data,
    output wire [19:0] ext_ram_addr,
    output wire [ 3:0] ext_ram_be_n,
    output wire        ext_ram_ce_n,
    output wire        ext_ram_oe_n,
    output wire        ext_ram_we_n,

    input wire        rxd,
    output wire       txd

);
  localparam  MasterInst = 1'b0;
  localparam  MasterData = 1'b1;

  localparam  [1:0] TargetBaseRam = 2'b00;
  localparam  [1:0] TargetExtRam = 2'b01;
  localparam  [1:0] TargetUart = 2'b10;


  localparam  [1:0] Idle = 2'b00;
  localparam  [1:0] Trigger = 2'b01;
  localparam  [1:0] Wait = 2'b10;
  localparam  [1:0] Result = 2'b11;


  assign inst_sram_addr_ok = (state == Idle) ? (data_sram_req ? 1'b0 : inst_sram_req) : 1'b0;
  assign data_sram_addr_ok = (state == Idle) & data_sram_req;

  wire [31:0] request_addr;
  wire [ 1:0] request_target;
  wire [ 1:0] request_size;
  wire [ 3:0] request_wstrb;
  wire [31:0] request_wdata;
  wire        request_wr;

  assign request_addr = data_sram_addr_ok ? data_sram_addr : inst_sram_addr;
  //   assign request_target = request_addr[31:20] >= 12'800 && request_addr[31:20] <= 12'803 ? target_base_ram :
  //          request_addr[31:20] >= 12'804 && request_addr[31:20] <= 12'807 ? target_ext_ram :
  //          target_uart;
  assign request_target = request_addr[31:23] == 9'b1000_0000_0 ?
         (request_addr[22] ? TargetExtRam : TargetBaseRam) : TargetUart;
  // assign request_size = data_sram_addr_ok ? data_sram_size : inst_sram_size;
  assign request_wstrb = data_sram_addr_ok ? data_sram_wstrb : 0;
  assign request_wdata = data_sram_addr_ok ? data_sram_wdata : 0;
  assign request_wr = data_sram_addr_ok ? data_sram_wr : inst_sram_wr;

  reg [19:0] reg_base_ram_request_addr;
  reg [ 1:0] reg_base_ram_request_size;
  reg [ 3:0] reg_base_ram_request_wstrb;
  reg [31:0] reg_base_ram_request_wdata;
  reg        reg_base_ram_request_wr;

  reg [19:0] reg_ext_ram_request_addr;
  reg [ 1:0] reg_ext_ram_request_size;
  reg [ 3:0] reg_ext_ram_request_wstrb;
  reg [31:0] reg_ext_ram_request_wdata;
  reg        reg_ext_ram_request_wr;


  reg        reg_uart_request_addr;  // 0xBFD003F8(后3位 000) 0xBFD003FC （后3位 100）
  reg [7:0] reg_uart_request_wdata;
  reg        reg_uart_request_wr;

  reg        trigger_base_ram;
  reg        trigger_ext_ram;
  reg        trigger_uart;
  //   assign request_wbn   = data_sram_addr_ok ? data_sram_wstrb : 0;

  //   wire [3:0] size_decode =
  //        request_size==2'd0 ?
  //        {request_addr[1:0]==2'd3,request_addr[1:0]==2'd2,request_addr[1:0]==2'd1,request_addr[1:0]==2'd0} :
  //        request_size==2'd1 ?
  //        {request_addr[1],request_addr[1],~request_addr[1],~request_addr[1]} :
  //        4'hf;



  reg [ 1:0] state;

  reg        reg_master;
  reg        reg_data_ok;
  reg [31:0] reg_rdata;

  assign inst_sram_data_ok = reg_master == MasterInst ? reg_data_ok : 1'b0;
  assign inst_sram_rdata   = reg_master == MasterInst ? reg_rdata : 32'h0;
  assign data_sram_data_ok = reg_master == MasterData ? reg_data_ok : 1'b0;
  assign data_sram_rdata   = reg_master == MasterData ? reg_rdata : 32'h0;

  initial begin
    reg_data_ok <= 1'b0;
    trigger_base_ram <= 1'b0;
    trigger_ext_ram <= 1'b0;
    trigger_uart <= 1'b0;
  end

  always @(posedge clk) begin
    if (reset) begin
      state <= Idle;
      reg_data_ok <= 1'b0;
    end else begin
      case (state)
        Idle: begin
          // if (request_target == target_base_ram || request_target == target_ext_ram) begin
          //   state <= Busy;
          //   if (request_target == target_base_ram) begin
          //     reg_base_ram_request_addr <= request_addr;
          //     reg_base_ram_request_size <= request_size;
          //     reg_base_ram_request_wstrb <= request_wstrb;
          //     reg_base_ram_request_wdata <= request_wdata;
          //     reg_base_ram_request_wr <= request_wr;
          //   end
          reg_data_ok <= 1'b0;
          trigger_base_ram <= 1'b0;
          trigger_ext_ram <= 1'b0;
          trigger_uart <= 1'b0;
          if (inst_sram_addr_ok || data_sram_addr_ok) begin
            if (inst_sram_addr_ok) begin
              reg_master <= MasterInst;
            end else begin
              reg_master <= MasterData;
            end
            if (request_target == TargetBaseRam) begin
              trigger_base_ram <= 1'b1;
              reg_base_ram_request_wr <= request_wr;
              reg_base_ram_request_addr <= request_addr[21:2];
              reg_base_ram_request_size <= request_size;
              reg_base_ram_request_wstrb <= request_wstrb;
              reg_base_ram_request_wdata <= request_wdata;
            end else if (request_target == TargetExtRam) begin
              trigger_ext_ram <= 1'b1;
              reg_ext_ram_request_wr <= request_wr;
              reg_ext_ram_request_addr <= request_addr[21:2];
              reg_ext_ram_request_size <= request_size;
              reg_ext_ram_request_wstrb <= request_wstrb;
              reg_ext_ram_request_wdata <= request_wdata;
            end else if (request_target == TargetUart) begin
              trigger_uart <= 1'b1;
              reg_uart_request_wr <= request_wr;
              reg_uart_request_addr <= request_addr[2];
              reg_uart_request_wdata <= request_wdata[7:0];
            end
            state <= Trigger;
          end else begin
            state <= Idle;
          end
        end
        Trigger: begin
          if (trigger_base_ram || trigger_ext_ram || trigger_uart) begin
            trigger_base_ram <= 1'b0;
            trigger_ext_ram <= 1'b0;
            trigger_uart <= 1'b0;
          end
          if (base_ram_data_ready || base_ram_writing_finished
            || ext_ram_data_ready ||  ext_ram_writing_finished
            || uart_data_ok) begin
            reg_data_ok <= 1'b1;
            reg_rdata <= (base_ram_data_ready) ? base_ram_rdata : 
                         (ext_ram_data_ready) ? ext_ram_rdata :
                         {24'b0, uart_rdata};
            state <= Idle;
          end else begin
            state <= Trigger;
          end
        end
        default: begin
          state <= Idle;
        end
      endcase
    end
  end

  sram_ctrl3 base_ram (
      .clk(clk),
      .start_operation(trigger_base_ram),
      .rw(~reg_base_ram_request_wr),
      .address_input(reg_base_ram_request_addr),
      .data_f2s(reg_base_ram_request_wdata),
      .wstrb(reg_base_ram_request_wstrb),

      .address_to_sram_output(base_ram_addr),
      .we_to_sram_output(base_ram_we_n),
      .oe_to_sram_output(base_ram_oe_n),
      .ce_to_sram_output(base_ram_ce_n),
      .be_to_sram_output(base_ram_be_n),
      .data_from_to_sram_input_output(base_ram_data),

      .writing_finished_signal_output(base_ram_writing_finished),
      .data_ready_signal_output(base_ram_data_ready),
      .data_s2f(base_ram_rdata),
      .busy_signal_output()
  );

  wire base_ram_writing_finished;
  wire base_ram_data_ready;
  wire [31:0] base_ram_rdata;

  wire ext_ram_writing_finished;
  wire ext_ram_data_ready;
  wire [31:0] ext_ram_rdata;

  sram_ctrl3 ext_ram (
      .clk(clk),
      .start_operation(trigger_ext_ram),
      .rw(~reg_ext_ram_request_wr),
      .address_input(reg_ext_ram_request_addr),
      .data_f2s(reg_ext_ram_request_wdata),
      .wstrb(reg_ext_ram_request_wstrb),

      .address_to_sram_output(ext_ram_addr),
      .we_to_sram_output(ext_ram_we_n),
      .oe_to_sram_output(ext_ram_oe_n),
      .ce_to_sram_output(ext_ram_ce_n),
      .be_to_sram_output(ext_ram_be_n),
      .data_from_to_sram_input_output(ext_ram_data),

      .writing_finished_signal_output(ext_ram_writing_finished),
      .data_ready_signal_output(ext_ram_data_ready),
      .data_s2f(ext_ram_rdata),
      .busy_signal_output()
  );

  wire uart_data_ok;
  wire [7:0] uart_rdata;
  uart uart (
    .i_uart_req(trigger_uart),
    .i_uart_wr(reg_uart_request_wr),
    .i_uart_addr(reg_uart_request_addr),
    .i_uart_wdata(reg_uart_request_wdata),
    .o_uart_data_ok(uart_data_ok),
    .o_uart_rdata(uart_rdata),
    .clk(clk),
    .reset(reset),

    .rxd(rxd),
    .txd(txd)
  );
endmodule
