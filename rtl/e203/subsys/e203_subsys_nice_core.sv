//=====================================================================
//
// Designer   : FyF
//
// Description:
//  The Module to realize NICE core
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
    output [1:0]                  nice_icb_cmd_size    ,

    // Memory lsu_rsp
    input                         nice_icb_rsp_valid   ,
    output                        nice_icb_rsp_ready   ,
    input  [`E203_XLEN-1:0]       nice_icb_rsp_rdata   ,
    input                         nice_icb_rsp_err

  );

  parameter L_WIDTH = 32;
  parameter S_WIDTH = 8;

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
  wire custom3            = (opcode == 7'b1111011);
  wire custom3_load_conv1 = custom3 && (func3 == 3'b010) && (func7 == 7'b0001011);
  wire custom3_load_conv2 = custom3 && (func3 == 3'b010) && (func7 == 7'b0001100);
  wire custom3_load_fc1   = custom3 && (func3 == 3'b010) && (func7 == 7'b0001101);
  wire custom3_load_fc2   = custom3 && (func3 == 3'b010) && (func7 == 7'b0001110);
  wire custom3_load_input = custom3 && (func3 == 3'b110) && (func7 == 7'b0001111);

  ////////////////////////////////////////////////////////////
  //  multi-cyc op
  ////////////////////////////////////////////////////////////
  wire custom_multi_cyc_op = custom3_load_conv1 | custom3_load_conv2 | custom3_load_fc1 | 
                             custom3_load_fc2   | custom3_load_input;
  // need access memory
  wire custom_mem_op       = custom3_load_conv1 | custom3_load_conv2 | custom3_load_fc1 | 
                             custom3_load_fc2   | custom3_load_input;

  ////////////////////////////////////////////////////////////
  // NICE FSM
  ////////////////////////////////////////////////////////////
  localparam IDLE       = 4'd0;
  localparam LOAD_CONV1 = 4'd1;
  localparam LOAD_CONV2 = 4'd2;
  localparam LOAD_FC1   = 4'd3;
  localparam LOAD_FC2   = 4'd4;
  localparam LOAD_INPUT = 4'd5;
  localparam MOVE_CONV1 = 4'd6;
  localparam CAL_CONV1  = 4'd7;
  localparam MOVE_CONV2 = 4'd8;
  localparam CAL_CONV2  = 4'd9;
  localparam MOVE_FC1   = 4'd10;
  localparam CAL_FC1    = 4'd11;
  localparam MOVE_FC2   = 4'd12;
  localparam CAL_FC2    = 4'd13;

  // FSM state register
  integer state;

  wire state_is_idle       = (state == IDLE);
  wire state_is_load_conv1 = (state == LOAD_CONV1);
  wire state_is_load_conv2 = (state == LOAD_CONV2);
  wire state_is_load_fc1   = (state == LOAD_FC1);
  wire state_is_load_fc2   = (state == LOAD_FC2);
  wire state_is_load_input = (state == LOAD_INPUT);
  wire state_is_move_conv1 = (state == MOVE_CONV1);
  wire state_is_cal_conv1  = (state == CAL_CONV1);
  wire state_is_move_conv2 = (state == MOVE_CONV2);
  wire state_is_cal_conv2  = (state == CAL_CONV2);
  wire state_is_move_fc1   = (state == MOVE_FC1);
  wire state_is_cal_fc1    = (state == CAL_FC1);
  wire state_is_move_fc2   = (state == MOVE_FC2);
  wire state_is_cal_fc2    = (state == CAL_FC2);

  wire state_is_move       = state_is_move_conv1 | state_is_move_conv2 | 
                             state_is_move_fc1   | state_is_move_fc2;

  // handshake success signals
  wire nice_req_hsked;
  wire nice_icb_rsp_hsked;
  wire nice_rsp_hsked;

  // finish signals
  wire load_conv1_done;
  wire load_conv2_done;
  wire load_fc1_done;
  wire load_fc2_done;
  wire load_input_done;
  wire move_conv1_done;
  wire cal_conv1_done;
  wire move_conv2_done;
  wire cal_conv2_done;
  wire move_fc1_done;
  wire cal_fc1_done;
  wire move_fc2_done;
  wire cal_fc2_done;

  integer conv2_cha_cnt;
  integer fc1_block_cnt;
  integer fc2_block_cnt;

  // FSM state update using behavioral description
  always @(posedge nice_clk or negedge nice_rst_n)
  begin
    if (!nice_rst_n) begin
      state <= IDLE;  // Reset state to IDLE
      conv2_cha_cnt <= 0;
      fc1_block_cnt <= 0;
      fc2_block_cnt <= 0;
    end else begin
      case (state)
        IDLE: begin
          if (nice_req_hsked && custom_multi_cyc_op) begin
            if (custom3_load_conv1)
              state <= LOAD_CONV1;
            else if (custom3_load_conv2)
              state <= LOAD_CONV2;
            else if (custom3_load_fc1)
              state <= LOAD_FC1;
            else if (custom3_load_fc2)
              state <= LOAD_FC2;
            else if (custom3_load_input)
              state <= LOAD_INPUT;
            else
              state <= IDLE;
          end
          else begin
            state <= IDLE;
          end
        end
        
        LOAD_CONV1: begin
          if (load_conv1_done)
            state <= IDLE;
          else
            state <= LOAD_CONV1;
        end

        LOAD_CONV2: begin
          if (load_conv2_done)
            state <= IDLE;
          else
            state <= LOAD_CONV2;
        end

        LOAD_FC1: begin
          if (load_fc1_done)
            state <= IDLE;
          else
            state <= LOAD_FC1;
        end

        LOAD_FC2: begin
          if (load_fc2_done)
            state <= IDLE;
          else
            state <= LOAD_FC2;
        end

        LOAD_INPUT: begin
          if (load_input_done)
            state <= MOVE_CONV1;
          else
            state <= LOAD_INPUT;
        end

        MOVE_CONV1: begin
          if (move_conv1_done)
            state <= CAL_CONV1;
          else
            state <= MOVE_CONV1;
        end

        CAL_CONV1: begin
          if (cal_conv1_done)
            state <= MOVE_CONV2;
          else
            state <= CAL_CONV1;
        end

        MOVE_CONV2: begin
          if (move_conv2_done)
            state <= CAL_CONV2;
          else
            state <= MOVE_CONV2;
        end

        CAL_CONV2: begin
          if (cal_conv2_done) begin
            if (conv2_cha_cnt < 4) begin
              state <= MOVE_CONV2;
              conv2_cha_cnt <= conv2_cha_cnt + 1;
            end else begin
              state <= MOVE_FC1;
              conv2_cha_cnt <= 0;
            end
          end
          else
            state <= CAL_CONV2;
        end

        MOVE_FC1: begin
          if (move_fc1_done)
            state <= CAL_FC1;
          else
            state <= MOVE_FC1;
        end

        CAL_FC1: begin
          if (cal_fc1_done) begin
            if (fc1_block_cnt < 3) begin
              state <= MOVE_FC1;
              fc1_block_cnt <= fc1_block_cnt + 1;
            end else begin
              state <= MOVE_FC2;
              fc1_block_cnt <= 0;
            end
          end
          else
            state <= CAL_FC1;
        end

        MOVE_FC2: begin
          if (move_fc2_done)
            state <= CAL_FC2;
          else
            state <= MOVE_FC2;
        end

        CAL_FC2: begin
          if (cal_fc2_done) begin
            if (fc2_block_cnt < 1) begin
              state <= MOVE_FC2;
              fc2_block_cnt <= fc2_block_cnt + 1;
            end else begin
              state <= IDLE;
              fc2_block_cnt <= 0;
            end
          end
          else
            state <= CAL_FC2;
        end

        default:
          state <= IDLE;
      endcase
    end
  end


  typedef logic        [7:0]  uint8_t;
  typedef logic signed [7:0]  int8_t;
  typedef logic signed [31:0] int32_t;
  typedef logic signed [8:0]  int9_t;

  localparam uint8_t input_zp = 127;

  localparam uint8_t conv1_weight_zp = 2;
  localparam int32_t conv1_bias[5] = '{871, -16316, -9617, -21527, -7265};
  localparam uint8_t conv1_out_zp = 159;

  localparam uint8_t conv2_weight_zp = 31;
  localparam int32_t conv2_bias[5] = '{-215, 2005, -2292, 4127, 441};
  localparam uint8_t conv2_out_zp = 118;

  localparam uint8_t fc1_weight_zp = 7;
  localparam int32_t fc1_bias[10] = '{-318, -434, 1721, -288, -879, 872, -658, -665, 2352, -2272};
  localparam uint8_t fc1_out_zp = 107;

  localparam uint8_t fc2_weight_zp = 11;
  localparam int32_t fc2_bias[10] = '{-5, 88, -71, -14, -2, -32, 22, 28, -64, 19};


  ////////////////////////////////////////////////////////////
  // instr EXU
  ////////////////////////////////////////////////////////////
  //////////// 1. custom3_load_conv1

  localparam CONV1_NUM        = 5;
  localparam CONV1_WIDTH      = 3;
  localparam CONV1_RC         = CONV1_WIDTH * CONV1_WIDTH; // 9
  localparam CONV1_SIZE       = CONV1_NUM * CONV1_RC;      // 45
  localparam CONV1_CNT_CYCLES = 12; // CONV1_SIZE/4

  integer load_conv1_cnt;

  wire load_conv1_cnt_done    = (load_conv1_cnt == CONV1_CNT_CYCLES);
  wire load_conv1_icb_rsp_hs  = state_is_load_conv1   & nice_icb_rsp_hsked;
  wire load_conv1_cnt_incr    = load_conv1_icb_rsp_hs & ~load_conv1_cnt_done;
  assign load_conv1_done      = load_conv1_icb_rsp_hs & load_conv1_cnt_done;

  // load_conv1_cnt accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      load_conv1_cnt <= 0;
    else 
    if (load_conv1_done)
      load_conv1_cnt <= 0;
    else if (load_conv1_cnt_incr)
      load_conv1_cnt <= load_conv1_cnt + 1;
    else
      load_conv1_cnt <= load_conv1_cnt;
  end

  // valid signals
  wire nice_rsp_valid_load_conv1     = state_is_load_conv1 & load_conv1_cnt_done & nice_icb_rsp_valid;
  wire nice_icb_cmd_valid_load_conv1 = state_is_load_conv1 & (load_conv1_cnt < CONV1_CNT_CYCLES);

  // conv1_weight
  int8_t conv1_weight_flat [CONV1_SIZE];
  int8_t conv1_weight [CONV1_NUM][CONV1_RC];

  // Constant connection, no resource consumption
  generate
    for (genvar n = 0; n < CONV1_NUM; n++) begin
      for (genvar r = 0; r < CONV1_RC; r++) begin
        assign conv1_weight[n][r] = conv1_weight_flat[n * CONV1_RC + r];
      end
    end
  endgenerate

  logic [$clog2(CONV1_SIZE):0] conv1_wptr;

  // conv1 buffer data storage
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      conv1_weight_flat <= '{default: '0};
      conv1_wptr <= 0;
    end 
    else if (load_conv1_cnt_incr && (conv1_wptr < CONV1_SIZE)) begin
      for (int b = 0; b < 4; b++) begin
        if ((conv1_wptr + b) < CONV1_SIZE)
          conv1_weight_flat[conv1_wptr + b] <= int8_t'(nice_icb_rsp_rdata[8*b +: 8]);
      end
      conv1_wptr <= conv1_wptr + 4;
    end
  end


//////////// 2. custom3_load_conv2
  localparam CONV2_NUM        = 5;
  localparam CONV2_CHA        = 5;
  localparam CONV2_WIDTH      = 3;
  localparam CONV2_RC         = CONV2_WIDTH * CONV2_WIDTH;        // 9
  localparam CONV2_SIZE       = CONV2_NUM * CONV2_RC * CONV2_CHA; // 45
  localparam CONV2_CNT_CYCLES = 57;

  integer load_conv2_cnt;

  wire load_conv2_cnt_done    = (load_conv2_cnt == CONV2_CNT_CYCLES);
  wire load_conv2_icb_rsp_hs  = state_is_load_conv2   & nice_icb_rsp_hsked;
  wire load_conv2_cnt_incr    = load_conv2_icb_rsp_hs & ~load_conv2_cnt_done;
  assign load_conv2_done      = load_conv2_icb_rsp_hs & load_conv2_cnt_done;

  // load_conv2_cnt accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      load_conv2_cnt <= 0;
    else 
    if (load_conv2_done)
      load_conv2_cnt <= 0;
    else if (load_conv2_cnt_incr)
      load_conv2_cnt <= load_conv2_cnt + 1;
    else
      load_conv2_cnt <= load_conv2_cnt;
  end

  // valid signals
  wire nice_rsp_valid_load_conv2     = state_is_load_conv2 & load_conv2_cnt_done & nice_icb_rsp_valid;
  wire nice_icb_cmd_valid_load_conv2 = state_is_load_conv2 & (load_conv2_cnt < CONV2_CNT_CYCLES);

  // conv2_weight
  int8_t conv2_weight_flat [CONV2_SIZE];
  int8_t conv2_weight [CONV2_NUM][CONV2_CHA][CONV2_RC];

  generate
    for (genvar n = 0; n < CONV2_NUM; n++) begin
      for (genvar c = 0; c < CONV2_CHA; c++) begin
        for (genvar r = 0; r < CONV2_RC; r++) begin
          assign conv2_weight[n][c][r] = conv2_weight_flat[n * (CONV2_CHA*CONV2_RC) + c * CONV2_RC + r];
        end
      end
    end
  endgenerate

  logic [$clog2(CONV2_SIZE):0] conv2_wptr;

  // conv2 buffer data storage
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      conv2_weight_flat <= '{default: '0};
      conv2_wptr <= 0;
    end 
    else if (load_conv2_cnt_incr && (conv2_wptr < CONV2_SIZE)) begin
      for (int b = 0; b < 4; b++) begin
        if ((conv2_wptr + b) < CONV2_SIZE)
          conv2_weight_flat[conv2_wptr + b] <= int8_t'(nice_icb_rsp_rdata[8*b +: 8]);
      end
      conv2_wptr <= conv2_wptr + 4;
    end
  end


  //////////// 3. custom3_load_fc1
  localparam FC1_OUT_WIDTH  = 10;
  localparam FC1_IN_WIDTH   = 20;
  localparam FC1_SIZE       = FC1_OUT_WIDTH * FC1_IN_WIDTH;  // 200
  localparam FC1_CNT_CYCLES = 50;

  integer load_fc1_cnt;

  wire load_fc1_cnt_done    = (load_fc1_cnt == FC1_CNT_CYCLES);
  wire load_fc1_icb_rsp_hs  = state_is_load_fc1   & nice_icb_rsp_hsked;
  wire load_fc1_cnt_incr    = load_fc1_icb_rsp_hs & ~load_fc1_cnt_done;
  assign load_fc1_done      = load_fc1_icb_rsp_hs & load_fc1_cnt_done;

  // load_fc1_cnt accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      load_fc1_cnt <= 0;
    else 
    if (load_fc1_cnt_done)
      load_fc1_cnt <= 0;
    else if (load_fc1_cnt_incr)
      load_fc1_cnt <= load_fc1_cnt + 1;
    else
      load_fc1_cnt <= load_fc1_cnt;
  end

  // valid signals
  wire nice_rsp_valid_load_fc1     = state_is_load_fc1 & load_fc1_cnt_done & nice_icb_rsp_valid;
  wire nice_icb_cmd_valid_load_fc1 = state_is_load_fc1 & (load_fc1_cnt < FC1_CNT_CYCLES);

  // fc1_weight
  int8_t fc1_weight_flat [FC1_SIZE];
  int8_t fc1_weight [FC1_OUT_WIDTH][FC1_IN_WIDTH];

  generate
    for (genvar o = 0; o < FC1_OUT_WIDTH; o++) begin
      for (genvar i = 0; i < FC1_IN_WIDTH; i++) begin
        assign fc1_weight[o][i] = fc1_weight_flat[o * FC1_IN_WIDTH + i];
      end
    end
  endgenerate

  logic [$clog2(FC1_SIZE):0] fc1_wptr;

  // fc1 buffer data storage
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      fc1_weight_flat <= '{default: '0};
      fc1_wptr <= 0;
    end 
    else if (load_fc1_cnt_incr && (fc1_wptr < FC1_SIZE)) begin
      for (int b = 0; b < 4; b++) begin
        if ((fc1_wptr + b) < FC1_SIZE)
          fc1_weight_flat[fc1_wptr + b] <= int8_t'(nice_icb_rsp_rdata[8*b +: 8]);
      end
      fc1_wptr <= fc1_wptr + 4;
    end
  end


  //////////// 4. custom3_load_fc2
  localparam FC2_OUT_WIDTH  = 10;
  localparam FC2_IN_WIDTH   = 10;
  localparam FC2_SIZE       = FC2_OUT_WIDTH * FC2_IN_WIDTH;  // 100
  localparam FC2_CNT_CYCLES = 25;

  integer load_fc2_cnt;

  wire load_fc2_cnt_done    = (load_fc2_cnt == FC2_CNT_CYCLES);
  wire load_fc2_icb_rsp_hs  = state_is_load_fc2   & nice_icb_rsp_hsked;
  wire load_fc2_cnt_incr    = load_fc2_icb_rsp_hs & ~load_fc2_cnt_done;
  assign load_fc2_done      = load_fc2_icb_rsp_hs & load_fc2_cnt_done;

  // load_fc2_cnt accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      load_fc2_cnt <= 0;
    else 
    if (load_fc2_cnt_done)
      load_fc2_cnt <= 0;
    else if (load_fc2_cnt_incr)
      load_fc2_cnt <= load_fc2_cnt + 1;
    else
      load_fc2_cnt <= load_fc2_cnt;
  end

  // valid signals
  wire nice_rsp_valid_load_fc2     = state_is_load_fc2 & load_fc2_cnt_done & nice_icb_rsp_valid;
  wire nice_icb_cmd_valid_load_fc2 = state_is_load_fc2 & (load_fc2_cnt < FC2_CNT_CYCLES);


  // fc2_weight
  int8_t fc2_weight_flat [FC2_SIZE];
  int8_t fc2_weight [FC2_OUT_WIDTH][FC2_IN_WIDTH];

  generate
    for (genvar o = 0; o < FC2_OUT_WIDTH; o++) begin
      for (genvar i = 0; i < FC2_IN_WIDTH; i++) begin
        assign fc2_weight[o][i] = fc2_weight_flat[o * FC2_IN_WIDTH + i];
      end
    end
  endgenerate

  logic [$clog2(FC2_SIZE):0] fc2_wptr;

  // fc2 buffer data storage
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      fc2_weight_flat <= '{default: '0};
      fc2_wptr <= 0;
    end 
    else if (load_fc2_cnt_incr && (fc2_wptr < FC2_SIZE)) begin
      for (int b = 0; b < 4; b++) begin
        if ((fc2_wptr + b) < FC2_SIZE)
          fc2_weight_flat[fc2_wptr + b] <= int8_t'(nice_icb_rsp_rdata[8*b +: 8]);
      end
      fc2_wptr <= fc2_wptr + 4;
    end
  end


  //////////// 5. custom3_load_input
  localparam INPUT_WIDTH      = 28;
  localparam INPUT_SIZE       = INPUT_WIDTH * INPUT_WIDTH;  // 784
  localparam INPUT_CNT_CYCLES = 196;

  integer load_input_cnt;

  wire load_input_cnt_done    = (load_input_cnt == INPUT_CNT_CYCLES);
  wire load_input_icb_rsp_hs  = state_is_load_input   & nice_icb_rsp_hsked;
  wire load_input_cnt_incr    = load_input_icb_rsp_hs & ~load_input_cnt_done;
  assign load_input_done      = load_input_icb_rsp_hs & load_input_cnt_done;

  // load_input_cnt accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      load_input_cnt <= 0;
    else 
    if (load_input_done)
      load_input_cnt <= 0;
    else if (load_input_cnt_incr)
      load_input_cnt <= load_input_cnt + 1;
    else
      load_input_cnt <= load_input_cnt;
  end

  // valid signals
  wire nice_icb_cmd_valid_load_input = state_is_load_input & (load_input_cnt < INPUT_CNT_CYCLES);

  // input_weight
  uint8_t input_reg_flat [INPUT_SIZE];
  uint8_t input_reg [INPUT_WIDTH][INPUT_WIDTH];

  generate
    for (genvar i = 0; i < INPUT_WIDTH; i++) begin
      for (genvar j = 0; j < INPUT_WIDTH; j++) begin
        assign input_reg[i][j] = input_reg_flat[i * INPUT_WIDTH + j];
      end
    end
  endgenerate

  logic [$clog2(INPUT_SIZE):0] input_wptr;

  // input buffer data storage
  always @(posedge nice_clk or negedge nice_rst_n) begin : READ_INPUT
    if (!nice_rst_n) begin
      input_reg_flat <= '{default: '0};
      input_wptr <= 0;
    end 
    else if (load_input_cnt_incr && (input_wptr < INPUT_SIZE)) begin
      for (int b = 0; b < 4; b++) begin
        if ((input_wptr + b) < INPUT_SIZE)
        input_reg_flat[input_wptr + b] <= uint8_t'(nice_icb_rsp_rdata[8*b +: 8]);
      end
      input_wptr <= input_wptr + 4;
    end
    else if (load_input_cnt_done) begin
      input_wptr <= 0;
    end
  end


  ////////////////////////////////////////////////////////////
  // SYSTOLIC ARRAY 
  ////////////////////////////////////////////////////////////
  parameter int SA_ROWS = 10;
  parameter int SA_COLS = 5;

  logic   [SA_ROWS-1:0]    sa_en_left;
  int9_t                   sa_data_left [SA_ROWS];
  logic   [SA_COLS-1:0]    sa_en_up;
  int32_t                  sa_data_up   [SA_COLS];
  logic   [SA_COLS-1:0]    sa_en_down;
  int32_t                  sa_data_down [SA_COLS];
  logic                    sa_mode      [SA_ROWS][SA_COLS];

  systolic_array_10_5 #(
    .L_WIDTH(L_WIDTH),
    .S_WIDTH(S_WIDTH),
    .ROWS(SA_ROWS),
    .COLS(SA_COLS)
  ) u_systolic_array_10_5 (
    .clk       (nice_clk),
    .rst_n     (nice_rst_n),

    .en_left   (sa_en_left),
    .data_left (sa_data_left),

    .en_up     (sa_en_up),
    .data_up   (sa_data_up),

    .en_down   (sa_en_down),
    .data_down (sa_data_down),

    .mode      (sa_mode)
  );

  ////////////////////// move
  //////////// 6. move_conv1
  integer move_cnt;

  wire move_conv1_cnt_done    = (move_cnt == SA_ROWS) && state_is_move_conv1;
  wire move_conv2_cnt_done    = (move_cnt == SA_ROWS) && state_is_move_conv2;
  wire move_fc1_cnt_done      = (move_cnt == SA_ROWS) && state_is_move_fc1;
  wire move_fc2_cnt_done      = (move_cnt == SA_ROWS) && state_is_move_fc2;
  assign move_conv1_done      = move_conv1_cnt_done;
  assign move_conv2_done      = move_conv2_cnt_done;
  assign move_fc1_done        = move_fc1_cnt_done;
  assign move_fc2_done        = move_fc2_cnt_done;

  wire move_cnt_done          = move_conv1_cnt_done | move_conv2_cnt_done | 
                                move_fc1_cnt_done   | move_fc2_cnt_done;
  
  // move_cnt accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin : MOVE_CNT
    if (!nice_rst_n)
      move_cnt <= 0;
    else 
    if (state_is_move) begin
      if (move_cnt_done)
        move_cnt <= 0;
      else
        move_cnt <= move_cnt + 1;
    end
  end

  reg [($clog2(FC1_OUT_WIDTH))*2-1:0]  fc1_move_select_row_idx[SA_COLS];
  reg [($clog2(FC1_IN_WIDTH))*2-1:0]   fc1_move_select_col_idx;

  // fc1 move select idx accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
        fc1_move_select_row_idx <= '{default: '0};
        fc1_move_select_col_idx <= '0;
    end
    else if (cal_conv1_done) begin  // init fc1 move select idx
      for (int i = 0; i < SA_COLS; i++) begin
        fc1_move_select_row_idx[i] <= $unsigned(i);   // 0~4
      end
      fc1_move_select_col_idx <= 'd9;                 // 9
    end
    else if (cal_fc1_done) begin
      if (fc1_block_cnt == 0) begin
        for (int i = 0; i < SA_COLS; i++) begin      
          fc1_move_select_row_idx[i] <= $unsigned(i); // 0~4
        end
        fc1_move_select_col_idx <= 'd19;              // 19
      end
      else if (fc1_block_cnt == 1) begin
        for (int i = 0; i < SA_COLS; i++) begin      
          fc1_move_select_row_idx[i] <= $unsigned(i+5); // 5~9
        end
        fc1_move_select_col_idx <= 'd9;                 // 9
      end
      else if (fc1_block_cnt == 2) begin
        for (int i = 0; i < SA_COLS; i++) begin      
          fc1_move_select_row_idx[i] <= $unsigned(i+5); // 5~9
        end
        fc1_move_select_col_idx <= 'd19;                // 19
      end
    end
    else if (state_is_move_fc1) begin
      fc1_move_select_col_idx <= fc1_move_select_col_idx - 1;
    end
  end

  reg [($clog2(FC2_OUT_WIDTH))*2-1:0]  fc2_move_select_row_idx[SA_COLS];
  reg [($clog2(FC2_IN_WIDTH))*2-1:0]   fc2_move_select_col_idx;

  // fc2 move select idx accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
        fc2_move_select_row_idx <= '{default: '0};
        fc2_move_select_col_idx <= '0;
    end
    else if (cal_conv1_done) begin  // init fc2 move select idx
      for (int i = 0; i < SA_COLS; i++) begin
        fc2_move_select_row_idx[i] <= $unsigned(i);     // 0~4
      end
      fc2_move_select_col_idx <= 'd9;                   // 9
    end
    else if (cal_fc2_done) begin
      if (fc2_block_cnt == 0) begin
        for (int i = 0; i < SA_COLS; i++) begin      
          fc2_move_select_row_idx[i] <= $unsigned(i+5); // 5~9
        end
        fc2_move_select_col_idx <= 'd9;                 // 9
      end
    end
    else if (state_is_move_fc2) begin
      fc2_move_select_col_idx <= fc2_move_select_col_idx - 1;
    end
  end

  // send weight to SA after sub zero_point
  int9_t weight_res[SA_COLS-1:0];

  // input:  weight / weight_zp
  // output: weight_res => sa_data_up
  // dequant weight by sub zero_point
  always_comb begin
    for (int i = 0; i < SA_COLS; i++) begin
      if (state_is_move_conv1) begin
        weight_res[i] = conv1_weight[i][CONV1_RC-1-move_cnt] - $signed(conv1_weight_zp);
      end
      else if (state_is_move_conv2) begin
        weight_res[i] = conv2_weight[i][conv2_cha_cnt][CONV1_RC-1-move_cnt] - $signed(conv2_weight_zp);
      end
      else if (state_is_move_fc1) begin
        weight_res[i] = fc1_weight[fc1_move_select_row_idx[i]][fc1_move_select_col_idx] - $signed(fc1_weight_zp);
      end
      else if (state_is_move_fc2) begin
        weight_res[i] = fc2_weight[fc2_move_select_row_idx[i]][fc2_move_select_col_idx] - $signed(fc2_weight_zp);
      end
      else begin
        weight_res[i] = '0; // default
      end
    end
  end

  // move kernels to systolic array
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if(!nice_rst_n) begin
      sa_en_up    <= '0;
      sa_data_up  <= '{default: '0};
      sa_mode     <= '{default: 1'b0};
    end
    else if (state_is_move) begin
      if (move_cnt == 0) begin                                    // 0
        sa_mode   <= '{default: 1'b1};
        sa_en_up  <= {SA_COLS{1'b1}};
        for (int i = 0; i < SA_COLS; i++) begin
          sa_data_up[i] <= weight_res[i];
        end
      end
      else if ((move_cnt >= 1) && (move_cnt <= SA_ROWS-2)) begin  // 1~8
        for (int i = 0; i < SA_COLS; i++) begin
          sa_data_up[i] <= weight_res[i];
        end
      end
      else if (move_cnt == SA_ROWS-1) begin                       // 9
        if (state_is_move_conv1 | state_is_move_conv2) begin
          sa_data_up  <= '{default: '0};
        end else if (state_is_move_fc1 | state_is_move_fc2) begin
          for (int i = 0; i < SA_COLS; i++) begin
            sa_data_up[i] <= weight_res[i];
          end
        end
      end
      else begin                                                  // default
        sa_en_up    <= '0;
        sa_data_up  <= '{default: '0};
        sa_mode     <= '{default: 1'b0};
      end
    end
    else begin                                                    // default
      sa_en_up    <= '0;
      sa_data_up  <= '{default: '0};
      sa_mode     <= '{default: 1'b0};
    end
  end

  ////////////////////// cal
  //////////// 7. cal_conv1
  localparam CONV1_SELECT_WIDTH = INPUT_WIDTH - CONV1_WIDTH * 2;            // 22
  localparam POOL1_OUTPUT_WIDTH = INPUT_WIDTH / 2;                          // 14
  localparam CONV1_OUTPUT_WIDTH = POOL1_OUTPUT_WIDTH - CONV1_WIDTH + 1;     // 12
  localparam CONV1_OUTPUT_SIZE  = CONV1_OUTPUT_WIDTH * CONV1_OUTPUT_WIDTH;  // 144
  localparam CAL_CONV1_CYCLES   = CONV1_OUTPUT_SIZE + CONV1_RC + SA_COLS;   // 158

  integer cal_conv1_cnt;
  wire cal_conv1_cnt_done    = (cal_conv1_cnt == CAL_CONV1_CYCLES);
  wire cal_conv1_icb_rsp_hs  = state_is_cal_conv1;
  wire cal_conv1_cnt_incr    = cal_conv1_icb_rsp_hs & ~cal_conv1_cnt_done;
  assign cal_conv1_done      = cal_conv1_icb_rsp_hs & cal_conv1_cnt_done;

  // cal_conv1_cnt accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      cal_conv1_cnt <= 0;
    else 
    if (cal_conv1_done)
      cal_conv1_cnt <= 0;
    else if (cal_conv1_cnt_incr)
      cal_conv1_cnt <= cal_conv1_cnt + 1;
    else
      cal_conv1_cnt <= cal_conv1_cnt;
  end

  reg [($clog2(CONV1_SELECT_WIDTH))*2-1:0]  conv1_input_select_row_idx[CONV1_RC];
  reg [($clog2(CONV1_SELECT_WIDTH))*2-1:0]  conv1_input_select_col_idx[CONV1_RC];

  // input matrix move to SA index accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      conv1_input_select_row_idx <= '{default: '0};
      conv1_input_select_col_idx <= '{default: '0};
    end 
    else if (cal_conv1_done) begin
      conv1_input_select_row_idx <= '{default: '0};
      conv1_input_select_col_idx <= '{default: '0};
    end
    else if (cal_conv1_cnt) begin // >=1
      for (int i = 0; i < CONV1_RC; i++) begin
        if (conv1_input_select_col_idx[i] == CONV1_SELECT_WIDTH) begin
            conv1_input_select_col_idx[i] <= 0;
          if (conv1_input_select_row_idx[i] == CONV1_SELECT_WIDTH)
            conv1_input_select_row_idx[i] <= 0;
          else
            conv1_input_select_row_idx[i] <= conv1_input_select_row_idx[i] + 2;
        end 
        else begin
          if (i <= cal_conv1_cnt-1)
          conv1_input_select_col_idx[i] <= conv1_input_select_col_idx[i] + 2;
        end
      end
    end
  end

  reg [$clog2(CONV1_OUTPUT_WIDTH)-1:0]  conv1_output_store_row_idx[CONV1_NUM];
  reg [$clog2(CONV1_OUTPUT_WIDTH)-1:0]  conv1_output_store_col_idx[CONV1_NUM];

  // conv1 output buffer index accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      conv1_output_store_row_idx <= '{default: '0};
      conv1_output_store_col_idx <= '{default: '0};
    end 
    else if (cal_conv1_done) begin
      conv1_output_store_row_idx <= '{default: '0};
      conv1_output_store_col_idx <= '{default: '0};
    end
    else if (cal_conv1_cnt >= (SA_ROWS + 1)) begin // >=11
      for (int i = 0; i < CONV1_NUM; i++) begin
        if (conv1_output_store_col_idx[i] == CONV1_OUTPUT_WIDTH - 1) begin
          conv1_output_store_col_idx[i] <= 0;
          if (conv1_output_store_row_idx[i] == CONV1_OUTPUT_WIDTH - 1)
            conv1_output_store_row_idx[i] <= 0;
          else
            conv1_output_store_row_idx[i] <= conv1_output_store_row_idx[i] + 1;
        end 
        else begin
          if (i < (cal_conv1_cnt - (CONV1_RC + 1)))
            conv1_output_store_col_idx[i] <= conv1_output_store_col_idx[i] + 1;
        end
      end
    end
  end
  
  //////////// 7. cal_conv2
  localparam CONV2_SELECT_WIDTH = CONV1_OUTPUT_WIDTH - CONV2_WIDTH * 2;     // 6
  localparam POOL2_OUTPUT_WIDTH = CONV1_OUTPUT_WIDTH / 2;                   // 6
  localparam CONV2_OUTPUT_WIDTH = POOL2_OUTPUT_WIDTH - CONV2_WIDTH + 1;     // 4
  localparam CONV2_OUTPUT_SIZE  = CONV2_OUTPUT_WIDTH * CONV2_OUTPUT_WIDTH;  // 16
  localparam CAL_CONV2_CYCLES   = CONV2_OUTPUT_SIZE + CONV2_RC + SA_COLS;   // 30

  integer cal_conv2_cnt;
  wire cal_conv2_cnt_done    = (cal_conv2_cnt == CAL_CONV2_CYCLES);
  wire cal_conv2_icb_rsp_hs  = state_is_cal_conv2;
  wire cal_conv2_cnt_incr    = cal_conv2_icb_rsp_hs & ~cal_conv2_cnt_done;
  assign cal_conv2_done      = cal_conv2_icb_rsp_hs & cal_conv2_cnt_done;

  // cal_conv2_cnt accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      cal_conv2_cnt <= 0;
    else 
    if (cal_conv2_done)
      cal_conv2_cnt <= 0;
    else if (cal_conv2_cnt_incr)
      cal_conv2_cnt <= cal_conv2_cnt + 1;
    else
      cal_conv2_cnt <= cal_conv2_cnt;
  end

  reg [($clog2(CONV2_SELECT_WIDTH))*2-1:0]  conv2_input_select_row_idx[CONV2_RC];
  reg [($clog2(CONV2_SELECT_WIDTH))*2-1:0]  conv2_input_select_col_idx[CONV2_RC];

  // input matrix move to SA index accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      conv2_input_select_row_idx <= '{default: '0};
      conv2_input_select_col_idx <= '{default: '0};
    end 
    else if (cal_conv2_done) begin
      conv2_input_select_row_idx <= '{default: '0};
      conv2_input_select_col_idx <= '{default: '0};
    end
    else if (cal_conv2_cnt) begin // >=1
      for (int i = 0; i < CONV2_RC; i++) begin
        if (conv2_input_select_col_idx[i] == CONV2_SELECT_WIDTH) begin
          conv2_input_select_col_idx[i] <= 0;
          if (conv2_input_select_row_idx[i] == CONV2_SELECT_WIDTH)
          conv2_input_select_row_idx[i] <= 0;
          else
            conv2_input_select_row_idx[i] <= conv2_input_select_row_idx[i] + 2;
        end 
        else begin
          if (i <= cal_conv2_cnt-1)
          conv2_input_select_col_idx[i] <= conv2_input_select_col_idx[i] + 2;
        end
      end
    end
  end

  reg [$clog2(CONV2_OUTPUT_WIDTH)-1:0]  conv2_output_store_row_idx[CONV2_NUM];
  reg [$clog2(CONV2_OUTPUT_WIDTH)-1:0]  conv2_output_store_col_idx[CONV2_NUM];

  // conv2 output buffer index accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      conv2_output_store_row_idx <= '{default: '0};
      conv2_output_store_col_idx <= '{default: '0};
    end 
    else if (cal_conv2_done) begin
      conv2_output_store_row_idx <= '{default: '0};
      conv2_output_store_col_idx <= '{default: '0};
    end
    else if (cal_conv2_cnt >= (SA_ROWS + 1)) begin // >=11
      for (int i = 0; i < CONV2_NUM; i++) begin
        if (conv2_output_store_col_idx[i] == CONV2_OUTPUT_WIDTH - 1) begin
          conv2_output_store_col_idx[i] <= 0;
          if (conv2_output_store_row_idx[i] == CONV2_OUTPUT_WIDTH - 1)
            conv2_output_store_row_idx[i] <= 0;
          else
            conv2_output_store_row_idx[i] <= conv2_output_store_row_idx[i] + 1;
        end 
        else begin
          if (i < (cal_conv2_cnt - (CONV2_RC + 1)))
            conv2_output_store_col_idx[i] <= conv2_output_store_col_idx[i] + 1;
        end
      end
    end
  end

  // conv and fc cal buffers
  uint8_t conv1_output_reg[CONV1_NUM][CONV1_OUTPUT_WIDTH][CONV1_OUTPUT_WIDTH];
  int32_t conv2_output_reg[CONV2_NUM][CONV2_OUTPUT_WIDTH][CONV2_OUTPUT_WIDTH];
  int32_t fc1_output_reg[FC1_OUT_WIDTH];

  //////////// 7. cal_fc1
  localparam POOL3_INPUT_SIZE   = CONV2_NUM * CONV2_OUTPUT_SIZE;  // 80
  localparam CAL_FC1_CYCLES     = FC1_OUT_WIDTH + SA_COLS + 1;    // 16

  integer cal_fc1_cnt;
  wire cal_fc1_cnt_done    = (cal_fc1_cnt == CAL_FC1_CYCLES);
  wire cal_fc1_icb_rsp_hs  = state_is_cal_fc1;
  wire cal_fc1_cnt_incr    = cal_fc1_icb_rsp_hs & ~cal_fc1_cnt_done;
  assign cal_fc1_done      = cal_fc1_icb_rsp_hs & cal_fc1_cnt_done;

  // cal_fc1_cnt accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin : CAL_FC1_CNT
    if (!nice_rst_n)
      cal_fc1_cnt <= 0;
    else 
    if (cal_fc1_done)
      cal_fc1_cnt <= 0;
    else if (cal_fc1_cnt_incr)
      cal_fc1_cnt <= cal_fc1_cnt + 1;
    else
      cal_fc1_cnt <= cal_fc1_cnt;
  end

  int32_t conv2_output_flat [POOL3_INPUT_SIZE];

  // convert conv2 output to 1D array
  always_comb begin : FLATTEN
    int idx;
    idx = 0;
    for (int ch = 0; ch < 5; ch++) begin
      // each 2 row and 2 col is a 2×2 block
      for (int r = 0; r < 4; r += 2) begin
        for (int c = 0; c < 4; c += 2) begin
          // (r,c) → (r,c+1) → (r+1,c) → (r+1,c+1)
          conv2_output_flat[idx] = conv2_output_reg[ch][r  ][c  ];
          idx = idx + 1;
          conv2_output_flat[idx] = conv2_output_reg[ch][r  ][c+1];
          idx = idx + 1;
          conv2_output_flat[idx] = conv2_output_reg[ch][r+1][c  ];
          idx = idx + 1;
          conv2_output_flat[idx] = conv2_output_reg[ch][r+1][c+1];
          idx = idx + 1;
        end
      end
    end
  end
  

  reg [$clog2(POOL3_INPUT_SIZE)-1:0] fc1_select_idx;

  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      fc1_select_idx <= '0;
    end 
    else if (cal_fc1_done) begin
      if ((fc1_block_cnt == 0) || (fc1_block_cnt == 2)) begin
        fc1_select_idx <= 'd40;
      end else begin
        fc1_select_idx <= '0;
      end
    end
    else if (cal_fc1_cnt >= 1) begin
      fc1_select_idx <= fc1_select_idx + 4;
    end 
  end

  //////////// 7. cal_fc2
  localparam CAL_FC2_CYCLES = FC2_OUT_WIDTH + SA_COLS + 2;   // 17

  integer cal_fc2_cnt;
  wire cal_fc2_cnt_done     = (cal_fc2_cnt == CAL_FC2_CYCLES);
  wire cal_fc2_icb_rsp_hs   = state_is_cal_fc2;
  wire cal_fc2_cnt_incr     = cal_fc2_icb_rsp_hs & ~cal_fc2_cnt_done;
  assign cal_fc2_done       = cal_fc2_icb_rsp_hs & cal_fc2_cnt_done;

  // cal_fc2_cnt accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin : CAL_FC2_CNT
    if (!nice_rst_n)
      cal_fc2_cnt <= 0;
    else 
    if (cal_fc2_done)
      cal_fc2_cnt <= 0;
    else if (cal_fc2_cnt_incr)
      cal_fc2_cnt <= cal_fc2_cnt + 1;
    else
      cal_fc2_cnt <= cal_fc2_cnt;
  end

  
  localparam int conv_row_offset[CONV1_RC] = '{0, 0, 0, 2, 2, 2, 4, 4, 4};
  localparam int conv_col_offset[CONV1_RC] = '{0, 2, 4, 0, 2, 4, 0, 2, 4};

  // send conv data to SA after pool and sub zero_point
  int9_t sa_input_res [SA_ROWS];

  // input:  input_reg / input_zp
  // output: sa_input_res => sa_data_left
  // dequant (and pool) input data by sub zero_point
  always_comb begin
    for (int i = 0; i < SA_ROWS; i++) begin
      uint8_t a[7]; 
      int9_t  quant;
      int9_t  max_int9;
      int9_t  zp_int9;

      if ((state_is_cal_conv1 && (cal_conv1_cnt <= (CONV1_OUTPUT_SIZE + CONV1_RC))) |
          (state_is_cal_conv2 && (cal_conv2_cnt <= (CONV2_OUTPUT_SIZE + CONV2_RC)))) begin
        if ((i >= 1) && ((i <= cal_conv1_cnt) | (i <= cal_conv2_cnt))) begin   // i: 1-9
          if (state_is_cal_conv1) begin
            a[0] = input_reg[conv1_input_select_row_idx[i-1]+conv_row_offset[i-1]  ][conv1_input_select_col_idx[i-1]+conv_col_offset[i-1]  ];
            a[1] = input_reg[conv1_input_select_row_idx[i-1]+conv_row_offset[i-1]  ][conv1_input_select_col_idx[i-1]+conv_col_offset[i-1]+1];
            a[2] = input_reg[conv1_input_select_row_idx[i-1]+conv_row_offset[i-1]+1][conv1_input_select_col_idx[i-1]+conv_col_offset[i-1]  ];
            a[3] = input_reg[conv1_input_select_row_idx[i-1]+conv_row_offset[i-1]+1][conv1_input_select_col_idx[i-1]+conv_col_offset[i-1]+1];
            zp_int9 = {1'b0, input_zp};
          end else if (state_is_cal_conv2) begin
            a[0] = conv1_output_reg[conv2_cha_cnt][conv2_input_select_row_idx[i-1]+conv_row_offset[i-1]  ][conv2_input_select_col_idx[i-1]+conv_col_offset[i-1]  ];
            a[1] = conv1_output_reg[conv2_cha_cnt][conv2_input_select_row_idx[i-1]+conv_row_offset[i-1]  ][conv2_input_select_col_idx[i-1]+conv_col_offset[i-1]+1];
            a[2] = conv1_output_reg[conv2_cha_cnt][conv2_input_select_row_idx[i-1]+conv_row_offset[i-1]+1][conv2_input_select_col_idx[i-1]+conv_col_offset[i-1]  ];
            a[3] = conv1_output_reg[conv2_cha_cnt][conv2_input_select_row_idx[i-1]+conv_row_offset[i-1]+1][conv2_input_select_col_idx[i-1]+conv_col_offset[i-1]+1];
            zp_int9 = {1'b0, conv1_out_zp};
          end else begin
            a[0] = '0;
            a[1] = '0;
            a[2] = '0;
            a[3] = '0;
            zp_int9 = '0;
          end
        end
      end else if (state_is_cal_fc1 && ((cal_fc1_cnt-1) == i)) begin
        a[0] = conv2_output_flat[fc1_select_idx];
        a[1] = conv2_output_flat[fc1_select_idx+1];
        a[2] = conv2_output_flat[fc1_select_idx+2];
        a[3] = conv2_output_flat[fc1_select_idx+3];
        zp_int9 = {1'b0, conv2_out_zp};
      end else if (state_is_cal_fc2 && ((cal_fc2_cnt-1) == i)) begin
        a[0] = fc1_output_reg[i];
        a[1] = fc1_output_reg[i];
        a[2] = fc1_output_reg[i];
        a[3] = fc1_output_reg[i];
        zp_int9 = {1'b0, fc1_out_zp};
      end else begin
        a[0] = '0;
        a[1] = '0;
        a[2] = '0;
        a[3] = '0;
        zp_int9 = '0;
      end

      // pool
      a[4] = (a[0] > a[1]) ? a[0] : a[1];
      a[5] = (a[2] > a[3]) ? a[2] : a[3];
      a[6] = (a[4] > a[5]) ? a[4] : a[5];
      max_int9 = {1'b0, a[6]};
      // dequant
      quant = max_int9 - zp_int9;

      sa_input_res[i] = quant;
    end
  end

  // receive conv output from SA and add bias and quant and clamp to uint8
  uint8_t sa_output_res [SA_COLS];

  // input:  sa_data_down / cal_bias / output_scale / output_zero_point
  // output: sa_output_res => output_reg
  // quant and clamp output data by add bias, divide scale and add zero_point then clamp and relu
  always_comb begin
    for (int i = 0; i < SA_COLS; i++) begin : OUTPUT_QUANT
      int32_t in;
      uint8_t res;
      in  = 32'sd0;
      res = 8'd0;

      // quant
      if (state_is_cal_conv1 && (cal_conv1_cnt >= (CONV1_RC + 1))) begin        // cal_conv1
        in = sa_data_down[i] + conv1_bias[i];
        // scale = 1/510 ≈ (1 + 1/256) / 512
        // (acc + acc/256) >> 9
        in = in + (in >>> 8);
        in = (in >>> 9) + int32_t'(conv1_out_zp);
        res = (in < int32_t'(conv1_out_zp)) ? conv1_out_zp :
              (in > 255) ? 8'd255 : uint8_t'(in);  // clamp to uint8 and relu
      end

      sa_output_res[i] = res;
    end
  end

  int32_t sa_output_sum [SA_COLS];

  // input:  output_reg / sa_data_down / out_zp
  // output: sa_output_sum
  // sum output and quant and clamp to uint8
  always_comb begin
    for (int i = 0; i < SA_COLS; i++) begin
      if (state_is_cal_conv2 && (cal_conv2_cnt >= (CONV2_RC + 1)) && (conv2_cha_cnt < 4)) begin        // cal_conv2 0-3
        sa_output_sum[i] = conv2_output_reg[i][conv2_output_store_row_idx[i]][conv2_output_store_col_idx[i]] + sa_data_down[i];
      end
      else if (state_is_cal_conv2 && (cal_conv2_cnt >= (CONV2_RC + 1)) && (conv2_cha_cnt == 4)) begin  // cal_conv2 4
        int32_t res;
        res = conv2_output_reg[i][conv2_output_store_row_idx[i]][conv2_output_store_col_idx[i]] + sa_data_down[i];
        // scale = 1/216 ≈ 1/256 + 1/1024 - 1/4096
        // (acc>>8) + (acc>>10) - (acc>>12)
        res = (res >>> 8) + (res >>> 10) - (res >>> 12);
        res = res + int32_t'(conv2_out_zp);
        res = (res < int32_t'(conv2_out_zp)) ? conv2_out_zp :
              (res > 255) ? 8'sd255 : res;  // clamp to uint8 and relu
        sa_output_sum[i] = res;
      end
      else if (state_is_cal_fc1 && (cal_fc1_cnt >= (FC1_OUT_WIDTH + 2)) && ((fc1_block_cnt == 0) || (fc1_block_cnt == 2))) begin // cal_fc1 0/2
        if ((fc1_block_cnt == 0) && (i == (cal_fc1_cnt-(FC1_OUT_WIDTH + 2)))) begin 
          sa_output_sum[i] = fc1_output_reg[i] + sa_data_down[i];
        end else if ((fc1_block_cnt == 2) && (i == (cal_fc1_cnt-(FC1_OUT_WIDTH + 2))))begin
          sa_output_sum[i] = fc1_output_reg[i+5] + sa_data_down[i];
        end else begin
          sa_output_sum[i] = '0;
        end 
      end
      else if (state_is_cal_fc1 && (cal_fc1_cnt >= (FC1_OUT_WIDTH + 2)) && ((fc1_block_cnt == 1) || (fc1_block_cnt == 3))) begin // cal_fc1 1/3
        int32_t res;
        if ((fc1_block_cnt == 1) && (i == (cal_fc1_cnt-(FC1_OUT_WIDTH + 2)))) begin 
          res = fc1_output_reg[i] + sa_data_down[i];
          // scale = 1/206  ≈ 1/256 + 1/1024
          // (acc>>8) + (acc>>10)
          res = (res >>> 8) + (res >>> 10);
          res = res + int32_t'(fc1_out_zp);
          res = (res < 0) ? 0 :
                (res > 255) ? 8'sd255 : res;  // clamp to uint8
        end else if ((fc1_block_cnt == 3) && (i == (cal_fc1_cnt-(FC1_OUT_WIDTH + 2)))) begin
          res = fc1_output_reg[i+5] + sa_data_down[i];
          res = (res >>> 8) + (res >>> 10);
          res = res + int32_t'(fc1_out_zp);
          res = (res < 0) ? 0 :
                (res > 255) ? 8'sd255 : res;  // clamp to uint8
        end else begin
          res = '0;
        end
        sa_output_sum[i] = res;
      end
      else if (state_is_cal_fc2 && (cal_fc2_cnt >= (FC2_OUT_WIDTH + 2)) && (i == (cal_fc2_cnt-(FC2_OUT_WIDTH + 2)))) begin // cal_fc2
        int32_t res;
        if (fc2_block_cnt == 0)
          res = sa_data_down[i] + fc2_bias[i];
        else
          res = sa_data_down[i] + fc2_bias[i+5];
        sa_output_sum[i] = res;
      end
      else begin
        sa_output_sum[i] = '0;
      end
    end 
  end

  int32_t result_max_buffer;
  int32_t result_max_idx;

  // Regesters:
  // int8_t  conv1_weight [CONV1_NUM][CONV1_RC];             5 * 9
  // int8_t  conv2_weight [CONV2_NUM][CONV2_CHA][CONV2_RC];  5 * 5 * 9
  // int8_t  fc1_weight [FC1_OUT_WIDTH][FC1_IN_WIDTH];       10 * 20
  // int8_t  fc2_weight [FC2_OUT_WIDTH][FC2_IN_WIDTH];       10 * 10
  // uint8_t input_reg [INPUT_WIDTH][INPUT_WIDTH];           28 * 28
  // uint8_t conv1_output_reg[CONV1_NUM][CONV1_OUTPUT_WIDTH][CONV1_OUTPUT_WIDTH];  5 * 12 * 12
  // int32_t conv2_output_reg[CONV2_NUM][CONV2_OUTPUT_WIDTH][CONV2_OUTPUT_WIDTH];  5 * 4 * 4
  // Move input data to systolic array, and store output data
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      sa_en_left        <= '0;
      sa_data_left      <= '{default: '0};
      conv1_output_reg  <= '{default: '0};
      conv2_output_reg  <= '{default: '0};
      fc1_output_reg    <= '{default: '0};
      result_max_buffer <= '0;
      result_max_idx    <= '0;
    end
    else if (state_is_cal_conv1 & (cal_conv1_cnt > 0)) begin
      if (cal_conv1_cnt == 1) begin // 1
        sa_en_left <= {{CONV1_RC{1'b1}}, 1'b0};
        sa_data_left[1] <= sa_input_res[1];
        for (int i = 0; i < CONV2_NUM; i++) begin
          for (int j = 0; j < CONV2_OUTPUT_WIDTH; j++) begin
            for (int k = 0; k < CONV2_OUTPUT_WIDTH; k++) begin
              conv2_output_reg[i][j][k] <= conv2_bias[i];
            end
          end
        end
        for (int i = 0; i < FC1_OUT_WIDTH; i++) begin
          fc1_output_reg[i] <= fc1_bias[i];
        end
        result_max_buffer <= 32'sh8000_0000;
        result_max_idx    <= 0;
      end 
      else if ((cal_conv1_cnt > 1) && (cal_conv1_cnt <= CONV1_RC)) begin // 2-9
        for (int i = 1; i <= CONV1_RC; i++) begin
          if (i <= cal_conv1_cnt)
              sa_data_left[i] <= sa_input_res[i];
      end
      end 
      else if (cal_conv1_cnt == (CONV1_RC + 1)) begin // 10
        for (int i = 1; i <= CONV1_RC; i++)
          sa_data_left[i] <= sa_input_res[i];
      end
      else if ((cal_conv1_cnt > (CONV1_RC + 1)) && (cal_conv1_cnt <= (CONV1_RC + 1 + CONV1_NUM))) begin // 11-15
        for (int i = 1; i <= CONV1_RC; i++)
          sa_data_left[i] <= sa_input_res[i];
        for (int i = 0; i < CONV1_NUM; i++) begin
          if (i < (cal_conv1_cnt - (CONV1_RC + 1)))
            conv1_output_reg[i][conv1_output_store_row_idx[i]][conv1_output_store_col_idx[i]] <= sa_output_res[i];
        end
      end
      else if ((cal_conv1_cnt > (CONV1_RC + 1 + CONV1_NUM)) && (cal_conv1_cnt <= CONV1_OUTPUT_SIZE)) begin // 16-144
        for (int i = 1; i <= CONV1_RC; i++)
          sa_data_left[i] <= sa_input_res[i];
        for (int i = 0; i < CONV1_NUM; i++) 
          conv1_output_reg[i][conv1_output_store_row_idx[i]][conv1_output_store_col_idx[i]] <= sa_output_res[i];
      end
      else if ((cal_conv1_cnt > CONV1_OUTPUT_SIZE) && (cal_conv1_cnt <= (CONV1_OUTPUT_SIZE + CONV1_RC))) begin // 145-153
        for (int i = 1; i <= CONV1_RC; i++) begin
          if (i > (cal_conv1_cnt - CONV1_OUTPUT_SIZE))
            sa_data_left[i] <= sa_input_res[i];
          else
            sa_data_left[i] <= '0;
        end
        for (int i = 0; i < CONV1_NUM; i++) 
          conv1_output_reg[i][conv1_output_store_row_idx[i]][conv1_output_store_col_idx[i]] <= sa_output_res[i];
        if (cal_conv1_cnt == (CONV1_OUTPUT_SIZE + CONV1_RC))
          sa_en_left <= '0;
      end
      else if ((cal_conv1_cnt > (CONV1_OUTPUT_SIZE + CONV1_RC)) && (cal_conv1_cnt <= (CONV1_OUTPUT_SIZE + CONV1_RC + SA_COLS))) begin // 154-158
        for (int i = 0; i < CONV1_NUM; i++) begin
          if (i >= (cal_conv1_cnt - (CONV1_OUTPUT_SIZE + CONV1_RC + 1)))
            conv1_output_reg[i][conv1_output_store_row_idx[i]][conv1_output_store_col_idx[i]] <= sa_output_res[i];
        end
      end
    end

    else if (state_is_cal_conv2 & (cal_conv2_cnt > 0)) begin
      if (cal_conv2_cnt == 1) begin // 1
        sa_en_left <= {{CONV2_RC{1'b1}}, 1'b0};
        sa_data_left[1] <= sa_input_res[1];
      end 
      else if ((cal_conv2_cnt > 1) && (cal_conv2_cnt <= CONV2_RC)) begin // 2-9
        for (int i = 1; i <= CONV2_RC; i++) begin
          if (i <= cal_conv2_cnt)
            sa_data_left[i] <= sa_input_res[i];
        end
      end 
      else if (cal_conv2_cnt == (CONV2_RC + 1)) begin // 10
        for (int i = 1; i <= CONV2_RC; i++)
          sa_data_left[i] <= sa_input_res[i];
      end
      else if ((cal_conv2_cnt > (CONV2_RC + 1)) && (cal_conv2_cnt <= (CONV2_RC + 1 + CONV2_NUM))) begin // 11-15
        for (int i = 1; i <= CONV1_RC; i++)
          sa_data_left[i] <= sa_input_res[i];
        for (int i = 0; i < CONV2_NUM; i++) begin
          if (i < (cal_conv2_cnt - (CONV2_RC + 1)))
            conv2_output_reg[i][conv2_output_store_row_idx[i]][conv2_output_store_col_idx[i]] <= sa_output_sum[i];
        end
      end
      else if ((cal_conv2_cnt > (CONV2_RC + 1 + CONV2_NUM)) && (cal_conv2_cnt <= CONV2_OUTPUT_SIZE)) begin // 16
        for (int i = 1; i <= CONV2_RC; i++)
          sa_data_left[i] <= sa_input_res[i];
        for (int i = 0; i < CONV2_NUM; i++) 
          conv2_output_reg[i][conv2_output_store_row_idx[i]][conv2_output_store_col_idx[i]] <= sa_output_sum[i];
      end
      else if ((cal_conv2_cnt > CONV2_OUTPUT_SIZE) && (cal_conv2_cnt <= (CONV2_OUTPUT_SIZE + CONV2_RC))) begin // 17-25
        for (int i = 1; i <= CONV2_RC; i++) begin
          if (i > (cal_conv2_cnt - CONV2_OUTPUT_SIZE))
            sa_data_left[i] <= sa_input_res[i];
          else
            sa_data_left[i] <= '0;
        end
        for (int i = 0; i < CONV2_NUM; i++) 
          conv2_output_reg[i][conv2_output_store_row_idx[i]][conv2_output_store_col_idx[i]] <= sa_output_sum[i];
        if (cal_conv2_cnt == (CONV2_OUTPUT_SIZE + CONV2_RC))
          sa_en_left <= '0;
      end
      else if ((cal_conv2_cnt > (CONV2_OUTPUT_SIZE + CONV2_RC)) && (cal_conv2_cnt <= (CONV2_OUTPUT_SIZE + CONV2_RC + SA_COLS))) begin // 26-30
        for (int i = 0; i < CONV2_NUM; i++) begin
          if (i >= (cal_conv2_cnt - (CONV2_OUTPUT_SIZE + CONV2_RC + 1)))
            conv2_output_reg[i][conv2_output_store_row_idx[i]][conv2_output_store_col_idx[i]] <= sa_output_sum[i];
        end
      end
    end

    else if (state_is_cal_fc1 & (cal_fc1_cnt > 0)) begin
      if (cal_fc1_cnt == 1) begin // 1
        sa_en_left <= {SA_ROWS{1'b1}};
        sa_data_left[0] <= sa_input_res[0];
      end 
      else if ((cal_fc1_cnt > 1) && (cal_fc1_cnt <= FC1_OUT_WIDTH)) begin // 2-10
        for (int i = 0; i < FC1_OUT_WIDTH; i++)
          sa_data_left[i] <= sa_input_res[i];
      end 
      else if (cal_fc1_cnt == (FC1_OUT_WIDTH + 1)) begin // 11
        sa_en_left <= {SA_ROWS{1'b0}};
        sa_data_left <= '{default: '0};
      end
      else if ((cal_fc1_cnt > (FC1_OUT_WIDTH + 1)) && (cal_fc1_cnt <= (FC1_OUT_WIDTH + 1 + SA_COLS))) begin // 12-16
        if (fc1_block_cnt <= 1)
          fc1_output_reg[cal_fc1_cnt-(FC1_OUT_WIDTH + 2)] <= sa_output_sum[cal_fc1_cnt-(FC1_OUT_WIDTH + 2)];
        else
          fc1_output_reg[5+cal_fc1_cnt-(FC1_OUT_WIDTH + 2)] <= sa_output_sum[cal_fc1_cnt-(FC1_OUT_WIDTH + 2)];
      end
    end

    else if (state_is_cal_fc2 & (cal_fc2_cnt > 0)) begin
      if (cal_fc2_cnt == 1) begin // 1
        sa_en_left <= {SA_ROWS{1'b1}};
        sa_data_left[0] <= sa_input_res[0];
      end 
      else if ((cal_fc2_cnt > 1) && (cal_fc2_cnt <= FC2_OUT_WIDTH)) begin // 2-10
        for (int i = 0; i < FC2_OUT_WIDTH; i++)
          sa_data_left[i] <= sa_input_res[i];
      end 
      else if (cal_fc2_cnt == (FC2_OUT_WIDTH + 1)) begin // 11
        sa_en_left <= {SA_ROWS{1'b0}};
        sa_data_left <= '{default: '0};
      end
      else if ((cal_fc2_cnt > (FC2_OUT_WIDTH + 1)) && (cal_fc2_cnt <= (FC2_OUT_WIDTH + 1 + SA_COLS))) begin // 12-16
        if (sa_output_sum[cal_fc2_cnt-(FC2_OUT_WIDTH + 2)] > result_max_buffer) begin
          result_max_buffer <= sa_output_sum[cal_fc2_cnt-(FC2_OUT_WIDTH + 2)];
          if (fc2_block_cnt == 0)
            result_max_idx  <= int32_t'(cal_fc2_cnt-(FC2_OUT_WIDTH + 2));
          else
            result_max_idx  <= int32_t'(5 + cal_fc2_cnt-(FC2_OUT_WIDTH + 2));
        end
      end
    end
  end


  wire nice_rsp_valid_load_input = state_is_cal_fc2 & (fc2_block_cnt == 1) & cal_fc2_done;


  ////////////////////////////////////////////////////////////////
  // Mem Access Addr Management
  ////////////////////////////////////////////////////////////////
  reg [`E203_XLEN-1:0] maddr_acc_r;  // Memory address accumulator register

  // Generate the command handshake signal
  wire nice_icb_cmd_hsked = nice_icb_cmd_valid & nice_icb_cmd_ready;

  // Determine individual enable signals for each operation
  wire load_conv1_maddr_ena = (state_is_idle & custom3_load_conv1 & nice_icb_cmd_hsked) | (state_is_load_conv1 & nice_icb_cmd_hsked);
  wire load_conv2_maddr_ena = (state_is_idle & custom3_load_conv2 & nice_icb_cmd_hsked) | (state_is_load_conv2 & nice_icb_cmd_hsked);
  wire load_fc1_maddr_ena   = (state_is_idle & custom3_load_fc1   & nice_icb_cmd_hsked) | (state_is_load_fc1   & nice_icb_cmd_hsked);
  wire load_fc2_maddr_ena   = (state_is_idle & custom3_load_fc2   & nice_icb_cmd_hsked) | (state_is_load_fc2   & nice_icb_cmd_hsked);
  wire load_input_maddr_ena = (state_is_idle & custom3_load_input & nice_icb_cmd_hsked) | (state_is_load_input & nice_icb_cmd_hsked);
  //wire conv_start_maddr_ena = (state_is_start_conv & conv_start_cmd_store);

  // Combine the enable signals for the memory address update
  wire maddr_ena = load_conv1_maddr_ena | load_conv2_maddr_ena | load_fc1_maddr_ena | 
                   load_fc2_maddr_ena   | load_input_maddr_ena;

  // When in IDLE state, use the base address from nice_req_rs1; otherwise, use the current accumulator value.
  wire maddr_ena_idle = (maddr_ena & state_is_idle); // | conv_start_cmd_store_first;
  wire [`E203_XLEN-1:0] maddr_acc_op1 = maddr_ena_idle ? nice_req_rs1 : 
                                        //(conv_start_cmd_store_first ? start_conv_rs1_reg : nice_req_rs1) : 
                                        maddr_acc_r;

  // The increment value is fixed (4 bytes)
  wire [`E203_XLEN-1:0] maddr_acc_op2 = `E203_XLEN'h4;

  // Compute the next accumulator value
  wire [`E203_XLEN-1:0] maddr_acc_next = maddr_acc_op1 + maddr_acc_op2;

  // Update the memory address accumulator using an always block.
  always @(posedge nice_clk or negedge nice_rst_n)
  begin
    if (!nice_rst_n)
      maddr_acc_r <= 0;
    else if (maddr_ena)
      maddr_acc_r <= maddr_acc_next;  // Update accumulator when enabled
    else
      maddr_acc_r <= maddr_acc_r;
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
  assign nice_rsp_valid = nice_rsp_valid_load_conv1 | nice_rsp_valid_load_conv2 | nice_rsp_valid_load_fc1 | 
                          nice_rsp_valid_load_fc2   | nice_rsp_valid_load_input;

  // When in the CAL_FC2 state, the response data is result_max_idx;
  // in other states, it is typically zero or unused here.
  assign nice_rsp_rdat  = {`E203_XLEN{state_is_cal_fc2}} & result_max_idx;

  // Indicate a memory access bus error if a valid memory response indicates an error.
  // (Optionally, an illegal-instruction check can also be included if needed.)
  assign nice_rsp_err   = (nice_icb_rsp_hsked & nice_icb_rsp_err);


  ////////////////////////////////////////////////////////////
  // Memory LSU (Load/Store Unit) for NICE operations
  ////////////////////////////////////////////////////////////

  // Always ready to accept memory responses
  assign nice_icb_rsp_ready = 1'b1;

  // Generate the memory command valid signal.
  assign nice_icb_cmd_valid =
         (state_is_idle & nice_req_valid & custom_mem_op)
         | nice_icb_cmd_valid_load_conv1
         | nice_icb_cmd_valid_load_conv2
         | nice_icb_cmd_valid_load_fc1
         | nice_icb_cmd_valid_load_fc2
         | nice_icb_cmd_valid_load_input;

  // Select the memory address. If in IDLE and about to start a memory operation,
  // use the base address from nice_req_rs1; otherwise, use the accumulated address.
  assign nice_icb_cmd_addr = (state_is_idle & custom_mem_op) ? nice_req_rs1 : 
                             //(conv_start_cmd_store_first) ? start_conv_rs1_reg :
                             maddr_acc_r;

  // Determine whether the operation is a read or write
  assign nice_icb_cmd_read = (state_is_idle & custom_mem_op)
         ? (custom3_load_conv1 | custom3_load_conv2 | custom3_load_fc1 | custom3_load_fc2 | custom3_load_input) : 1'b1;
        // : ((conv_start_maddr_ena) ? 1'b0 : 1'b1);

  // Select the write data when in SBUF state or about to start SBUF from IDLE.
  assign nice_icb_cmd_wdata = //conv_start_maddr_ena ? output_reg[output_cmd_num_idx][output_cmd_row_idx][output_cmd_col_idx] :
                              {`E203_XLEN{1'b0}};

  // The transaction size is fixed at word (2'b10).
  assign nice_icb_cmd_size = 2'b10;

  // Assert 'nice_mem_holdup' when in any multi-cycle memory state
  assign nice_mem_holdup = state_is_load_conv1 | state_is_load_conv2 | state_is_load_fc1 |
                           state_is_load_fc2   | state_is_load_input;


  ////////////////////////////////////////////////////////////
  // NICE Active Signal
  ////////////////////////////////////////////////////////////
  assign nice_active = state_is_idle ? nice_req_valid : 1'b1;

  
endmodule
`endif//}
