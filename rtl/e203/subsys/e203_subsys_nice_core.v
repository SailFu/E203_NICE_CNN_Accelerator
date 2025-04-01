//=====================================================================
//
// Designer   : LZB, FyF
//
// Description:
//  The Module to realize a simple NICE core
//
// ====================================================================
`include "e203_defines.v"

`ifdef E203_HAS_NICE//{
module e203_subsys_nice_core (
    // System
    input                         nice_clk             ,
    input                         nice_rst_n	         ,
    output                        nice_active	         ,
    output                        nice_mem_holdup	     ,
    //    output                        nice_rsp_err_irq	  ,

    // Control cmd_req
    input                         nice_req_valid       ,
    output                        nice_req_ready       ,
    input  [`E203_XLEN-1:0]       nice_req_inst        ,
    input  [`E203_XLEN-1:0]       nice_req_rs1         ,
    input  [`E203_XLEN-1:0]       nice_req_rs2         ,

    // Control cmd_rsp
    output                        nice_rsp_valid       ,
    input                         nice_rsp_ready       ,
    output [`E203_XLEN-1:0]       nice_rsp_rdat        ,
    output                        nice_rsp_err    	   ,

    // Memory lsu_req
    output                        nice_icb_cmd_valid   ,
    input                         nice_icb_cmd_ready   ,
    output [`E203_ADDR_SIZE-1:0]  nice_icb_cmd_addr    ,
    output                        nice_icb_cmd_read    ,
    output [`E203_XLEN-1:0]       nice_icb_cmd_wdata   ,
    //    output [`E203_XLEN_MW-1:0]     nice_icb_cmd_wmask   ,  //
    output [1:0]                  nice_icb_cmd_size    ,

    // Memory lsu_rsp
    input                         nice_icb_rsp_valid   ,
    output                        nice_icb_rsp_ready   ,
    input  [`E203_XLEN-1:0]       nice_icb_rsp_rdata   ,
    input                         nice_icb_rsp_err

  );

  localparam ROWBUF_DP = 4;
  localparam ROWBUF_IDX_W = 2;
  localparam ROW_IDX_W = 2;
  localparam COL_IDX_W = 4;
  localparam PIPE_NUM = 3;


  // here we only use custom3:
  // CUSTOM0 = 7'h0b, R type
  // CUSTOM1 = 7'h2b, R tpye
  // CUSTOM2 = 7'h5b, R type
  // CUSTOM3 = 7'h7b, R type

  // RISC-V format
  //	.insn r  0x33,  0,  0, a0, a1, a2       0:  00c58533[ 	]+add [ 	]+a0,a1,a2
  //	.insn i  0x13,  0, a0, a1, 13           4:  00d58513[ 	]+addi[ 	]+a0,a1,13
  //	.insn i  0x67,  0, a0, 10(a1)           8:  00a58567[ 	]+jalr[ 	]+a0,10 (a1)
  //	.insn s   0x3,  0, a0, 4(a1)            c:  00458503[ 	]+lb  [ 	]+a0,4(a1)
  //	.insn sb 0x63,  0, a0, a1, target       10: feb508e3[ 	]+beq [ 	]+a0,a1,0 target
  //	.insn sb 0x23,  0, a0, 4(a1)            14: 00a58223[ 	]+sb  [ 	]+a0,4(a1)
  //	.insn u  0x37, a0, 0xfff                18: 00fff537[ 	]+lui [ 	]+a0,0xfff
  //	.insn uj 0x6f, a0, target               1c: fe5ff56f[ 	]+jal [ 	]+a0,0 target
  //	.insn ci 0x1, 0x0, a0, 4                20: 0511    [ 	]+addi[ 	]+a0,a0,4
  //	.insn cr 0x2, 0x8, a0, a1               22: 852e    [ 	]+mv  [ 	]+a0,a1
  //	.insn ciw 0x0, 0x0, a1, 1               24: 002c    [ 	]+addi[ 	]+a1,sp,8
  //	.insn cb 0x1, 0x6, a1, target           26: dde9    [ 	]+beqz[ 	]+a1,0 target
  //	.insn cj 0x1, 0x5, target               28: bfe1    [ 	]+j   [ 	]+0 targe


  ////////////////////////////////////////////////////////////
  // decode
  ////////////////////////////////////////////////////////////
  wire [6:0] opcode = nice_req_valid ? nice_req_inst[6:0]   : 7'b0;
  wire [2:0] func3  = nice_req_valid ? nice_req_inst[14:12] : 3'b0;
  wire [6:0] func7  = nice_req_valid ? nice_req_inst[31:25] : 7'b0;

  ////////////////////////////////////////////////////////////
  // custom3:
  // Supported format: only R type here
  // Supported instr:
  //  1. custom3 lbuf: load data(in memory) to row_buf
  //     lbuf (a1)
  //     .insn r opcode, func3, func7, rd, rs1, rs2
  //  2. custom3 sbuf: store data(in row_buf) to memory
  //     sbuf (a1)
  //     .insn r opcode, func3, func7, rd, rs1, rs2
  //  3. custom3 acc rowsum: load data from memory(@a1), accumulate row datas and write back
  //     rowsum rd, a1, x0
  //     .insn r opcode, func3, func7, rd, rs1, rs2
  ////////////////////////////////////////////////////////////
  wire custom3 = (opcode == 7'b1111011);
  wire custom3_lbuf       = custom3 && (func3 == 3'b010) && (func7 == 7'b0000001);
  wire custom3_sbuf       = custom3 && (func3 == 3'b010) && (func7 == 7'b0000010);
  wire custom3_rowsum     = custom3 && (func3 == 3'b110) && (func7 == 7'b0000110);
  wire custom3_mul_loada  = custom3 && (func3 == 3'b001) && (func7 == 7'b0000001);
  wire custom3_mul_loadb  = custom3 && (func3 == 3'b001) && (func7 == 7'b0000010);
  wire custom3_mul_cals   = custom3 && (func3 == 3'b001) && (func7 == 7'b0000011);


  ////////////////////////////////////////////////////////////
  //  multi-cyc op
  ////////////////////////////////////////////////////////////
  wire custom_multi_cyc_op = custom3_lbuf      | custom3_sbuf      | custom3_rowsum | 
                             custom3_mul_loada | custom3_mul_loadb | custom3_mul_cals;
  // need access memory
  wire custom_mem_op       = custom3_lbuf      | custom3_sbuf      | custom3_rowsum | 
                             custom3_mul_loada | custom3_mul_loadb | custom3_mul_cals;

  ////////////////////////////////////////////////////////////
  // NICE FSM
  ////////////////////////////////////////////////////////////
  localparam IDLE       = 4'd0;
  localparam LBUF       = 4'd1;
  localparam SBUF       = 4'd2;
  localparam ROWSUM     = 4'd3;
  localparam MUL_LOADA  = 4'd4;
  localparam MUL_LOADB  = 4'd5;
  localparam MUL_CALS   = 4'd6;

  // FSM state register
  integer state;

  wire state_is_idle       = (state == IDLE);
  wire state_is_lbuf       = (state == LBUF);
  wire state_is_sbuf       = (state == SBUF);
  wire state_is_rowsum     = (state == ROWSUM);
  wire state_is_mul_loada  = (state == MUL_LOADA);
  wire state_is_mul_loadb  = (state == MUL_LOADB);
  wire state_is_mul_cals   = (state == MUL_CALS);

  // handshake success signals
  wire nice_req_hsked;
  wire nice_icb_rsp_hsked;
  wire nice_rsp_hsked;

  // finish signals
  wire lbuf_icb_rsp_hsked_last;
  wire sbuf_icb_rsp_hsked_last;
  wire rowsum_done;
  wire mul_loada_done;
  wire mul_loadb_done;
  wire mul_cals_done;

  // FSM state update using behavioral description
  always @(posedge nice_clk or negedge nice_rst_n)
  begin
    if (!nice_rst_n)
      state <= IDLE;  // Reset state to IDLE
    else
    begin
      case (state)
        // In IDLE, if a valid request occurs and the instruction is one of the supported custom3 ops,
        // transition to the corresponding state.
        IDLE:
        begin
          if (nice_req_hsked && custom_multi_cyc_op)
          begin
            if (custom3_lbuf)
              state <= LBUF;
            else if (custom3_sbuf)
              state <= SBUF;
            else if (custom3_rowsum)
              state <= ROWSUM;
            else if (custom3_mul_loada)
              state <= MUL_LOADA;
            else if (custom3_mul_loadb)
              state <= MUL_LOADB;
            else if (custom3_mul_cals)
              state <= MUL_CALS;
            else
              state <= IDLE;
          end
          else
          begin
            state <= IDLE;
          end
        end

        // In LBUF, remain until the last ICB response handshake occurs.
        LBUF:
        begin
          if (lbuf_icb_rsp_hsked_last)
            state <= IDLE;
          else
            state <= LBUF;
        end

        // In SBUF, remain until the last ICB response handshake occurs.
        SBUF:
        begin
          if (sbuf_icb_rsp_hsked_last)
            state <= IDLE;
          else
            state <= SBUF;
        end

        // In ROWSUM, remain until the row sum operation is completed.
        ROWSUM:
        begin
          if (rowsum_done)
            state <= IDLE;
          else
            state <= ROWSUM;
        end
        
        MUL_LOADA:
        begin
          if (mul_loada_done)
            state <= IDLE;
          else
            state <= MUL_LOADA;
        end

        MUL_LOADB:
        begin
          if (mul_loadb_done)
            state <= IDLE;
          else
            state <= MUL_LOADB;
        end

        MUL_CALS:
        begin
          if (mul_cals_done)
            state <= IDLE;
          else
            state <= MUL_CALS;
        end

        default:
          state <= IDLE;
      endcase
    end
  end



  ////////////////////////////////////////////////////////////
  // instr EXU
  ////////////////////////////////////////////////////////////
  wire [ROW_IDX_W-1:0]  clonum = 2'b10;  // fixed clonum
  //wire [COL_IDX_W-1:0]  rownum;

  //////////// 1. custom3_lbuf
  // lbuf counter register
  reg [ROWBUF_IDX_W-1:0] lbuf_cnt;

  // Combinational signals for counter update
  wire lbuf_cnt_last   = (lbuf_cnt == clonum);
  //wire lbuf_cnt_clr    = custom3_lbuf & nice_req_hsked;  // Clear counter when a new lbuf op is accepted
  wire lbuf_icb_rsp_hs = state_is_lbuf & nice_icb_rsp_hsked; // Memory response handshake in LBUF state
  wire lbuf_cnt_incr   = lbuf_icb_rsp_hs & ~lbuf_cnt_last;   // Increment counter if handshake occurs and counter is not full
  // Generate a signal indicating the last memory response handshake in LBUF state
  assign lbuf_icb_rsp_hsked_last = lbuf_icb_rsp_hs & lbuf_cnt_last; // and use in FSM

  // Sequential block updating the counter
  always @(posedge nice_clk or negedge nice_rst_n)
  begin
    if (!nice_rst_n)
      lbuf_cnt <= 0;
    else if (lbuf_icb_rsp_hsked_last)
      lbuf_cnt <= 0;
    else if (lbuf_cnt_incr)
      lbuf_cnt <= lbuf_cnt + 1;
    else
      lbuf_cnt <= lbuf_cnt;
  end

  // Valid signals
  // Generate response valid: asserted when in LBUF state, counter is full, and the memory response is valid
  wire nice_rsp_valid_lbuf = state_is_lbuf & lbuf_cnt_last & nice_icb_rsp_valid;
  // Generate memory command valid: asserted in LBUF state when counter is not yet full
  wire nice_icb_cmd_valid_lbuf = state_is_lbuf & (lbuf_cnt < clonum);


  //////////// 2. custom3_sbuf
  reg [ROWBUF_IDX_W-1:0] sbuf_cnt;

  // Generate handshake signals for SBUF
  // The memory response handshake is valid only in SBUF state.
  wire sbuf_icb_rsp_hsked = state_is_sbuf & nice_icb_rsp_hsked;
  // Determine if the SBUF counter has reached the fixed clonum
  wire sbuf_cnt_last = (sbuf_cnt == clonum);
  // Increment counter when a memory response handshake occurs
  wire sbuf_cnt_incr = sbuf_icb_rsp_hsked & ~sbuf_cnt_last;
  // Signal asserted when the last memory response handshake is received
  assign sbuf_icb_rsp_hsked_last = sbuf_icb_rsp_hsked & sbuf_cnt_last; // and use in FSM

  // SBUF counter update: clear when last response handshake is received,
  // increment when a response handshake occurs and the counter is not full.
  always @(posedge nice_clk or negedge nice_rst_n)
  begin
    if (!nice_rst_n)
      sbuf_cnt <= 0;
    else if (sbuf_icb_rsp_hsked_last)
      sbuf_cnt <= 0;
    else if (sbuf_cnt_incr)
      sbuf_cnt <= sbuf_cnt + 1;
    else
      sbuf_cnt <= sbuf_cnt;
  end

  // Valid signals
  // Generate SBUF response valid signal: asserted when in SBUF state, the counter is full, and the memory response is valid.
  wire nice_rsp_valid_sbuf = state_is_sbuf & sbuf_cnt_last & nice_icb_rsp_valid;

  wire nice_icb_cmd_hsked;

  // SBUF command counter: tracks the number of memory commands issued in SBUF state.
  reg [ROWBUF_IDX_W-1:0] sbuf_cmd_cnt;
  wire sbuf_cmd_cnt_last = (sbuf_cmd_cnt == clonum);

  // SBUF command handshake: same as above from the memory command side.
  wire sbuf_icb_cmd_hsked = ((state_is_sbuf) | (state_is_idle & custom3_sbuf)) & nice_icb_cmd_hsked;

  // SBUF command counter update: clear when the last memory response handshake occurs,
  // increment when a memory command handshake occurs and the command counter is not full.
  always @(posedge nice_clk or negedge nice_rst_n)
  begin
    if (!nice_rst_n)
      sbuf_cmd_cnt <= 0;
    else if (sbuf_icb_rsp_hsked_last)
      sbuf_cmd_cnt <= 0;
    else if (sbuf_icb_cmd_hsked && !sbuf_cmd_cnt_last)
      sbuf_cmd_cnt <= sbuf_cmd_cnt + 1;
    else
      sbuf_cmd_cnt <= sbuf_cmd_cnt;
  end

  // Generate memory command valid signal for SBUF: asserted in SBUF state when the command counter
  // is not full and the response counter has not yet reached clonum.
  wire nice_icb_cmd_valid_sbuf = state_is_sbuf & (sbuf_cmd_cnt <= clonum) & (sbuf_cnt != clonum);


  //////////// 3. custom3_rowsum
  // rowbuf counter
  reg [ROWBUF_IDX_W-1:0] rowbuf_cnt;

  // When in ROWSUM state, a memory response handshake occurs.
  wire rowbuf_icb_rsp_hsked = state_is_rowsum & nice_icb_rsp_hsked;

  // Check if the counter has reached the fixed 'clonum'
  wire rowbuf_cnt_last = (rowbuf_cnt == clonum);

  // Clear the counter when the last handshake is received
  wire rowbuf_cnt_clr = rowbuf_icb_rsp_hsked & rowbuf_cnt_last;

  // Increment the counter when a handshake occurs and the counter is not full
  wire rowbuf_cnt_incr = rowbuf_icb_rsp_hsked & ~rowbuf_cnt_last;

  wire nice_rsp_valid_rowsum;
  // Optionally, generate a handshake signal for the response (used elsewhere)
  wire rowbuf_rsp_hsked = nice_rsp_valid_rowsum & nice_rsp_ready;

  // Sequential block to update the row buffer counter
  always @(posedge nice_clk or negedge nice_rst_n)
  begin
    if (!nice_rst_n)
      rowbuf_cnt <= 0;                      // Reset counter to 0 on reset
    else if (rowbuf_cnt_clr)
      rowbuf_cnt <= 0;                      // Clear counter when last handshake occurs
    else if (rowbuf_cnt_incr)
      rowbuf_cnt <= rowbuf_cnt + 1;         // Increment counter if handshake occurs and not full
    else
      rowbuf_cnt <= rowbuf_cnt;             // Otherwise, keep the counter value
  end


  // recieve data buffer, to make sure rowsum ops come from registers
  // Control signal generation:
  // - rcv_data_buf_set: Triggered when a row-buffer memory response handshake occurs.
  // - rcv_data_buf_clr: Triggered when the row-buffer response handshake occurs.
  // - rcv_data_buf_ena: Enable signal for updating the data buffer and index.
  wire rcv_data_buf_set = rowbuf_icb_rsp_hsked;  // Set signal: triggered by memory response handshake in row-buffer
  wire rcv_data_buf_clr = rowbuf_rsp_hsked;      // Clear signal: triggered by row-buffer response handshake
  wire rcv_data_buf_ena = rcv_data_buf_set | rcv_data_buf_clr;

  // rcv_data_buf_valid: A flag indicating the data buffer has been updated.
  // This register simply latches the enable signal value.
  reg rcv_data_buf_valid;
  always @(posedge nice_clk or negedge nice_rst_n)
  begin
    if (!nice_rst_n)
      rcv_data_buf_valid <= 1'b0;
    else
      rcv_data_buf_valid <= rcv_data_buf_ena;
  end

  // rcv_data_buf: Data buffer to capture memory response data.
  // It updates with the memory response when enabled.
  reg [`E203_XLEN-1:0] rcv_data_buf;
  always @(posedge nice_clk or negedge nice_rst_n)
  begin
    if (!nice_rst_n)
      rcv_data_buf <= {`E203_XLEN{1'b0}};
    else if (rcv_data_buf_ena)
      rcv_data_buf <= nice_icb_rsp_rdata;
  end

  // rcv_data_buf_idx: Index register for the data buffer.
  // When the clear signal is asserted, it resets to 0;
  // when the set signal is asserted, it captures the current row buffer counter value.
  reg [ROWBUF_IDX_W-1:0] rcv_data_buf_idx;
  always @(posedge nice_clk or negedge nice_rst_n)
  begin
    if (!nice_rst_n)
      rcv_data_buf_idx <= 0;
    else if (rcv_data_buf_ena)
    begin
      if (rcv_data_buf_clr)
        rcv_data_buf_idx <= 0;
      else if (rcv_data_buf_set)
        rcv_data_buf_idx <= rowbuf_cnt;
    end
  end


  // rowsum accumulator
  // This block accumulates received data to form the row sum.
  // When a new data word is valid (rcv_data_buf_valid), if its index is 0, the accumulator is set
  // to the received value; otherwise, the received data is added to the current accumulator value.
  reg [`E203_XLEN-1:0] rowsum_acc;
  always @(posedge nice_clk or negedge nice_rst_n)
  begin
    if (!nice_rst_n)
      rowsum_acc <= 0;
    else if (rcv_data_buf_valid)
    begin
      if (rcv_data_buf_idx == 0)
        rowsum_acc <= rcv_data_buf;         // Set accumulator on first valid data
      else
        rowsum_acc <= rowsum_acc + rcv_data_buf; // Add subsequent data
    end
  end

  // Define rowsum_done as when in ROWSUM state and the response handshake occurs.
  assign rowsum_done = state_is_rowsum & nice_rsp_hsked;

  // The final row sum result is held in rowsum_acc.
  wire [`E203_XLEN-1:0] rowsum_res = rowsum_acc;

  // Define a flag for intermediate accumulation (i.e., when the received data is not the first element)
  wire rowsum_acc_flg = rcv_data_buf_valid & (rcv_data_buf_idx != 0);

  // Generate the response valid signal for rowsum:
  // It is asserted when in ROWSUM state, the received data index equals clonum,
  // and no intermediate accumulation is pending.
  assign nice_rsp_valid_rowsum = state_is_rowsum & (rcv_data_buf_idx == clonum) & ~rowsum_acc_flg;

  // Generate the command valid signal for rowsum:
  // It is asserted in ROWSUM state when the received data index is less than clonum and
  // no intermediate accumulation is pending.
  wire nice_icb_cmd_valid_rowsum = state_is_rowsum & (rcv_data_buf_idx < clonum) & ~rowsum_acc_flg;


  //////////// 4. custom3_mul_loada
  localparam matrix_size_A    = 16;

  integer mul_loada_cnt;

  wire mul_loada_cnt_done    = (mul_loada_cnt == matrix_size_A);
  wire mul_loada_icb_rsp_hs  = state_is_mul_loada & nice_icb_rsp_hsked;
  wire mul_loada_cnt_incr    = mul_loada_icb_rsp_hs & ~mul_loada_cnt_done;
  assign mul_loada_done      = mul_loada_icb_rsp_hs & mul_loada_cnt_done;

  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      mul_loada_cnt <= 0;
    else if (mul_loada_done)
      mul_loada_cnt <= 0;
    else if (mul_loada_cnt_incr)
      mul_loada_cnt <= mul_loada_cnt + 1;
    else
      mul_loada_cnt <= mul_loada_cnt;
  end

  // valid signals
  wire nice_rsp_valid_mul_loada     = state_is_mul_loada & mul_loada_cnt_done & nice_icb_rsp_valid;
  wire nice_icb_cmd_valid_mul_loada = state_is_mul_loada & mul_loada_cnt_incr;


  //////////// 5. custom3_mul_loadb






  //////////// matrix buffer
  reg [`E203_XLEN-1:0] matrix_A [0:matrix_size_A-1];

  integer i;

  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      for (i = 0; i < matrix_size_A; i = i + 1)
        matrix_A[i] <= {`E203_XLEN{1'b0}};
      end else if (mul_loada_icb_rsp_hs) begin
        matrix_A[mul_loada_cnt] <= nice_icb_rsp_rdata;
      end 
  end


  //////////// rowbuf
  // The row buffer supports three access modes:
  // 1. LBUF: Write data from memory into rowbuf at index "lbuf_cnt".
  // 2. ROWSUM: Update rowbuf at index "rcv_data_buf_idx" by accumulating the received data.
  // 3. SBUF: Read from rowbuf for store operations.

  reg [`E203_XLEN-1:0] rowbuf_r [0:ROWBUF_DP-1];

  always @(posedge nice_clk or negedge nice_rst_n)
  begin
    if (!nice_rst_n)
    begin
      for (i = 0; i < ROWBUF_DP; i = i + 1)
        rowbuf_r[i] <= {`E203_XLEN{1'b0}};
    end
    else
    begin
      // LBUF write: if in LBUF state and memory response handshake occurs,
      // write the memory response data to the row buffer at index given by lbuf_cnt.
      if (state_is_lbuf && nice_icb_rsp_hsked)
      begin
        rowbuf_r[lbuf_cnt] <= nice_icb_rsp_rdata;
      end

      // ROWSUM write: when new data is valid, update (accumulate) the row buffer entry.
      // The current value is read, added with the new data (rcv_data_buf), and written back.
      if (rcv_data_buf_valid)
      begin
        rowbuf_r[rcv_data_buf_idx] <= rowbuf_r[rcv_data_buf_idx] + rcv_data_buf;
      end
    end
  end

  // For SBUF operation, the read data can be obtained as:
  // wire [`E203_XLEN-1:0] sbuf_rdata = rowbuf_reg[sbuf_idx];
  // (where sbuf_idx is determined by the SBUF control logic)


  //////////// mem aacess addr management
  // The memory address accumulator is updated when any of the following operations
  // (custom3_lbuf, custom3_sbuf, custom3_rowsum) are enabled.
  // When in IDLE state, the accumulator starts with the base address from nice_req_rs1;
  // otherwise, it increments by 4 (word size) each time a memory command handshake occurs.

  reg [`E203_XLEN-1:0] maddr_acc_r;  // Memory address accumulator register

  // Generate the command handshake signal
  assign nice_icb_cmd_hsked = nice_icb_cmd_valid & nice_icb_cmd_ready;

  // Determine individual enable signals for each operation
  wire lbuf_maddr_ena       = (state_is_idle & custom3_lbuf       & nice_icb_cmd_hsked) | (state_is_lbuf       & nice_icb_cmd_hsked);
  wire sbuf_maddr_ena       = (state_is_idle & custom3_sbuf       & nice_icb_cmd_hsked) | (state_is_sbuf       & nice_icb_cmd_hsked);
  wire rowsum_maddr_ena     = (state_is_idle & custom3_rowsum     & nice_icb_cmd_hsked) | (state_is_rowsum     & nice_icb_cmd_hsked);
  wire mul_loada_maddr_ena  = (state_is_idle & custom3_mul_loada  & nice_icb_cmd_hsked) | (state_is_mul_loada  & nice_icb_cmd_hsked);
  wire mul_cals_maddr_ena   = (state_is_idle & custom3_mul_cals   & nice_icb_cmd_hsked) | (state_is_mul_cals   & nice_icb_cmd_hsked);

  // Combine the enable signals for the memory address update
  wire maddr_ena = lbuf_maddr_ena | sbuf_maddr_ena | rowsum_maddr_ena | mul_loada_maddr_ena | mul_cals_maddr_ena;

  // When in IDLE state, use the base address from nice_req_rs1; otherwise, use the current accumulator value.
  wire maddr_ena_idle = maddr_ena & state_is_idle;
  wire [`E203_XLEN-1:0] maddr_acc_op1 = maddr_ena_idle ? nice_req_rs1 : maddr_acc_r;

  // The increment value is fixed (4 bytes)
  wire [`E203_XLEN-1:0] maddr_acc_op2 = `E203_XLEN'h4;

  // Compute the next accumulator value
  wire [`E203_XLEN-1:0] maddr_acc_next = maddr_acc_op1 + maddr_acc_op2;

  // Update the memory address accumulator using an always block.
  always @(posedge nice_clk or negedge nice_rst_n)
  begin
    if (!nice_rst_n)
      maddr_acc_r <= 0;             // Reset the accumulator to 0 on reset
    else if (maddr_ena)
      maddr_acc_r <= maddr_acc_next;  // Update accumulator when enabled
    else
      maddr_acc_r <= maddr_acc_r;       // Otherwise, hold the current value
  end


  ////////////////////////////////////////////////////////////
  // Command Request (cmd_req) Logic
  ////////////////////////////////////////////////////////////

  // nice_req_hsked is a handshake signal indicating that a valid request
  // has been accepted (valid & ready).
  assign nice_req_hsked = nice_req_valid & nice_req_ready;

  // The NICE core can accept a request (nice_req_ready) if:
  // 1. It is in the IDLE state, and
  // 2. If the instruction involves memory operations, the memory command interface is ready;
  //    otherwise, no additional conditions are required.
  assign nice_req_ready = state_is_idle & (custom_mem_op ? nice_icb_cmd_ready : 1'b1);


  ////////////////////////////////////////////////////////////
  // Command Response (cmd_rsp) Logic
  ////////////////////////////////////////////////////////////

  // nice_rsp_hsked is a handshake signal indicating that a valid response
  // has been accepted (valid & ready).
  assign nice_rsp_hsked = nice_rsp_valid & nice_rsp_ready;

  // nice_icb_rsp_hsked is the memory response handshake (when a valid memory response
  // is accepted by the NICE core).
  assign nice_icb_rsp_hsked = nice_icb_rsp_valid & nice_icb_rsp_ready;

  // The NICE core provides a valid response if any of the three operations (rowsum, sbuf, lbuf)
  // signals a valid result.
  assign nice_rsp_valid = nice_rsp_valid_rowsum | nice_rsp_valid_sbuf | nice_rsp_valid_lbuf | nice_rsp_valid_mul_loada;

  // When in the ROWSUM state, the response data is the accumulated row sum;
  // in other states, it is typically zero or unused here.
  assign nice_rsp_rdat  = {`E203_XLEN{state_is_rowsum}} & rowsum_res;

  // Indicate a memory access bus error if a valid memory response indicates an error.
  // (Optionally, an illegal-instruction check can also be included if needed.)
  assign nice_rsp_err   = (nice_icb_rsp_hsked & nice_icb_rsp_err);


  ////////////////////////////////////////////////////////////
  // Memory LSU (Load/Store Unit) for NICE operations
  ////////////////////////////////////////////////////////////

  // Always ready to accept memory responses
  assign nice_icb_rsp_ready = 1'b1;

  // SBUF uses sbuf_cmd_cnt to index into rowbuf when writing to memory
  wire [ROWBUF_IDX_W-1:0] sbuf_idx = sbuf_cmd_cnt;

  // Generate the memory command valid signal. It is asserted if:
  // 1. In IDLE with a valid request that needs memory (custom_mem_op),
  // 2. LBUF logic indicates a need to read more data from memory,
  // 3. SBUF logic indicates a need to write data to memory,
  // 4. ROWSUM logic indicates a need to read additional data from memory.
  assign nice_icb_cmd_valid =
         (state_is_idle & nice_req_valid & custom_mem_op)
         | nice_icb_cmd_valid_lbuf
         | nice_icb_cmd_valid_sbuf
         | nice_icb_cmd_valid_rowsum
         | nice_icb_cmd_valid_mul_loada;

  // Select the memory address. If in IDLE and about to start a memory operation,
  // use the base address from nice_req_rs1; otherwise, use the accumulated address.
  assign nice_icb_cmd_addr = (state_is_idle & custom_mem_op) ? nice_req_rs1 : maddr_acc_r;

  // Determine whether the operation is a read or write:
  // - In IDLE, if the next operation is either LBUF or ROWSUM, use read.
  // - In SBUF state, use write.
  // - Otherwise, default to read.
  assign nice_icb_cmd_read = (state_is_idle & custom_mem_op)
         ? (custom3_lbuf | custom3_rowsum | custom3_mul_loada | custom3_mul_cals)
         : (state_is_sbuf ? 1'b0 : 1'b1);

  // Select the write data when in SBUF state or about to start SBUF from IDLE.
  assign nice_icb_cmd_wdata = (state_is_idle & custom3_sbuf)
         ? rowbuf_r[sbuf_idx]
         : (state_is_sbuf ? rowbuf_r[sbuf_idx] : {`E203_XLEN{1'b0}});

  // For simplicity, the write mask is not assigned in this design. If needed,
  // it can be set to select specific byte lanes (e.g., 4'b1111 for a full word).
  // assign nice_icb_cmd_wmask = {`sirv_XLEN_MW{custom3_sbuf}} & 4'b1111;

  // The transaction size is fixed at word (2'b10).
  assign nice_icb_cmd_size = 2'b10;

  // Assert 'nice_mem_holdup' when in any multi-cycle memory state
  // (LBUF, SBUF, or ROWSUM) to stall the core if necessary.
  assign nice_mem_holdup = state_is_lbuf | state_is_sbuf | state_is_rowsum ;


  ////////////////////////////////////////////////////////////
  // NICE Active Signal
  ////////////////////////////////////////////////////////////
  // The NICE core is active if there is a request in IDLE or if the FSM is
  // in any of the operational states (LBUF, SBUF, ROWSUM).
  assign nice_active = state_is_idle ? nice_req_valid : 1'b1;

  
endmodule
`endif//}
