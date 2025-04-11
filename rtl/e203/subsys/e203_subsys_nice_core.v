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
  wire custom3            = (opcode == 7'b1111011);
  wire custom3_mul_loada  = custom3 && (func3 == 3'b010) && (func7 == 7'b0001000);
  wire custom3_mul_loadb  = custom3 && (func3 == 3'b010) && (func7 == 7'b0001001);
  wire custom3_mul_cals   = custom3 && (func3 == 3'b010) && (func7 == 7'b0001010);

  ////////////////////////////////////////////////////////////
  //  multi-cyc op
  ////////////////////////////////////////////////////////////
  wire custom_multi_cyc_op = custom3_mul_loada | custom3_mul_loadb | custom3_mul_cals;
  // need access memory
  wire custom_mem_op       = custom3_mul_loada | custom3_mul_loadb;

  ////////////////////////////////////////////////////////////
  // NICE FSM
  ////////////////////////////////////////////////////////////
  localparam IDLE       = 4'd0;
  localparam MUL_LOADA  = 4'd1;
  localparam MUL_LOADB  = 4'd2;
  localparam MUL_STORE  = 4'd3;
  localparam MUL_CALS   = 4'd4;

  // FSM state register
  integer state;

  wire state_is_idle       = (state == IDLE);
  wire state_is_mul_loada  = (state == MUL_LOADA);
  wire state_is_mul_loadb  = (state == MUL_LOADB);
  wire state_is_mul_store  = (state == MUL_STORE);
  wire state_is_mul_cals   = (state == MUL_CALS);

  // handshake success signals
  wire nice_req_hsked;
  wire nice_icb_rsp_hsked;
  wire nice_rsp_hsked;

  // finish signals
  wire mul_loada_done;
  wire mul_loadb_done;
  wire mul_store_done;
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
            if (custom3_mul_loada)
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
            state <= MUL_STORE;
          else
            state <= MUL_LOADB;
        end

        MUL_STORE:
        begin
          if (mul_store_done)
            state <= IDLE;
          else
            state <= MUL_STORE;
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
  //////////// 1. custom3_mul_loada
  localparam matrix_size_A   = 16;

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
  wire nice_icb_cmd_valid_mul_loada = state_is_mul_loada & (mul_loada_cnt < matrix_size_A);


  //////////// 2. custom3_mul_loadb
  localparam matrix_size_B   = 12;
  localparam systolic_size   = 4; // systolic array size

  integer mul_loadb_cnt;

  wire mul_loadb_cnt_done    = (mul_loadb_cnt == matrix_size_B);
  wire mul_loadb_icb_rsp_hs  = state_is_mul_loadb & nice_icb_rsp_hsked;
  wire mul_loadb_cnt_incr    = mul_loadb_icb_rsp_hs & ~mul_loadb_cnt_done;
  assign mul_loadb_done      = mul_loadb_icb_rsp_hs & mul_loadb_cnt_done;

  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      mul_loadb_cnt <= 0;
    else if (mul_loadb_done)
      mul_loadb_cnt <= 0;
    else if (mul_loadb_cnt_incr)
      mul_loadb_cnt <= mul_loadb_cnt + 1;
    else
      mul_loadb_cnt <= mul_loadb_cnt;
  end

  // valid signals
  wire nice_rsp_valid_mul_loadb     = state_is_mul_loadb & mul_loadb_cnt_done & nice_icb_rsp_valid;
  wire nice_icb_cmd_valid_mul_loadb = state_is_mul_loadb & (mul_loadb_cnt < matrix_size_B);


  //////////// matrix_A buffer
  reg signed [`E203_XLEN-1:0] matrix_A_reg [0:matrix_size_A-1];

  integer i;

  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      for (i = 0; i < matrix_size_A; i = i + 1)
        matrix_A_reg[i] <= {`E203_XLEN{1'b0}};
      end else if (mul_loada_icb_rsp_hs) begin
        matrix_A_reg[mul_loada_cnt] <= $signed(nice_icb_rsp_rdata);
      end 
  end

  // matrix_B buffer
  reg signed [`E203_XLEN-1:0] matrix_B_reg [0:matrix_size_B-1];

  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      for (i = 0; i < matrix_size_B; i = i + 1)
        matrix_B_reg[i] <= {`E203_XLEN{1'b0}};
      end else if (mul_loadb_icb_rsp_hs) begin
        matrix_B_reg[mul_loadb_cnt] <= $signed(nice_icb_rsp_rdata);
      end 
  end


  ////////////////////////////////////////////////////////////
  // SYSTOLIC ARRAY 
  ////////////////////////////////////////////////////////////
  parameter DATA_WIDTH = 32;

  // left
  reg                           array_en_left_0_0,   array_en_left_1_0,   array_en_left_2_0,   array_en_left_3_0;
  reg  signed [DATA_WIDTH-1:0]  array_data_left_0_0, array_data_left_1_0, array_data_left_2_0, array_data_left_3_0;
  // up
  reg                           array_en_up_0_0,     array_en_up_0_1,     array_en_up_0_2,     array_en_up_0_3;
  reg  signed [DATA_WIDTH-1:0]  array_data_up_0_0,   array_data_up_0_1,   array_data_up_0_2,   array_data_up_0_3;
  // down
  wire                          array_en_down_3_0,   array_en_down_3_1,   array_en_down_3_2,   array_en_down_3_3;
  wire signed [DATA_WIDTH-1:0]  array_data_down_3_0, array_data_down_3_1, array_data_down_3_2, array_data_down_3_3;
  // control
  reg                           array_mode_0_0,      array_mode_0_1,      array_mode_0_2,      array_mode_0_3;
  reg                           array_mode_1_0,      array_mode_1_1,      array_mode_1_2,      array_mode_1_3;
  reg                           array_mode_2_0,      array_mode_2_1,      array_mode_2_2,      array_mode_2_3;
  reg                           array_mode_3_0,      array_mode_3_1,      array_mode_3_2,      array_mode_3_3;
  
  systolic_array_4_4 #(
    .DATA_WIDTH(DATA_WIDTH)
  ) u_systolic_array_4_4 (
    .array_clk      (nice_clk),
    .array_rst_n    (nice_rst_n),
    
    .array_en_left_0_0   (array_en_left_0_0),
    .array_en_left_1_0   (array_en_left_1_0),
    .array_en_left_2_0   (array_en_left_2_0),
    .array_en_left_3_0   (array_en_left_3_0),
    .array_data_left_0_0 (array_data_left_0_0),
    .array_data_left_1_0 (array_data_left_1_0),
    .array_data_left_2_0 (array_data_left_2_0),
    .array_data_left_3_0 (array_data_left_3_0),
    
    .array_en_up_0_0   (array_en_up_0_0),
    .array_en_up_0_1   (array_en_up_0_1),
    .array_en_up_0_2   (array_en_up_0_2),
    .array_en_up_0_3   (array_en_up_0_3),
    .array_data_up_0_0 (array_data_up_0_0),
    .array_data_up_0_1 (array_data_up_0_1),
    .array_data_up_0_2 (array_data_up_0_2),
    .array_data_up_0_3 (array_data_up_0_3),
    
    .array_en_down_3_0   (array_en_down_3_0),
    .array_en_down_3_1   (array_en_down_3_1),
    .array_en_down_3_2   (array_en_down_3_2),
    .array_en_down_3_3   (array_en_down_3_3),
    .array_data_down_3_0 (array_data_down_3_0),
    .array_data_down_3_1 (array_data_down_3_1),
    .array_data_down_3_2 (array_data_down_3_2),
    .array_data_down_3_3 (array_data_down_3_3),
    
    .array_mode_0_0 (array_mode_0_0),
    .array_mode_0_1 (array_mode_0_1),
    .array_mode_0_2 (array_mode_0_2),
    .array_mode_0_3 (array_mode_0_3),
    .array_mode_1_0 (array_mode_1_0),
    .array_mode_1_1 (array_mode_1_1),
    .array_mode_1_2 (array_mode_1_2),
    .array_mode_1_3 (array_mode_1_3),
    .array_mode_2_0 (array_mode_2_0),
    .array_mode_2_1 (array_mode_2_1),
    .array_mode_2_2 (array_mode_2_2),
    .array_mode_2_3 (array_mode_2_3),
    .array_mode_3_0 (array_mode_3_0),
    .array_mode_3_1 (array_mode_3_1),
    .array_mode_3_2 (array_mode_3_2),
    .array_mode_3_3 (array_mode_3_3)
  );

  integer store_cnt;
  wire store_cnt_done = (store_cnt == systolic_size);
  assign mul_store_done = store_cnt_done;

  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      store_cnt <= 0;
    else if (state_is_mul_store) begin
      if (store_cnt_done)
        store_cnt <= 0;
      else
        store_cnt <= store_cnt + 1;
    end
  end

  always @(posedge nice_clk or negedge nice_rst_n) begin                                        
    if(!nice_rst_n) begin
      array_en_up_0_0     <= 1'b0;
      array_en_up_0_1     <= 1'b0;
      array_en_up_0_2     <= 1'b0;
      array_en_up_0_3     <= 1'b0;
      array_data_up_0_0   <= {DATA_WIDTH{1'b0}};
      array_data_up_0_1   <= {DATA_WIDTH{1'b0}};
      array_data_up_0_2   <= {DATA_WIDTH{1'b0}};
      array_data_up_0_3   <= {DATA_WIDTH{1'b0}};
      array_mode_0_0 <= 1'b0; array_mode_0_1 <= 1'b0; array_mode_0_2 <= 1'b0; array_mode_0_3 <= 1'b0;
      array_mode_1_0 <= 1'b0; array_mode_1_1 <= 1'b0; array_mode_1_2 <= 1'b0; array_mode_1_3 <= 1'b0;
      array_mode_2_0 <= 1'b0; array_mode_2_1 <= 1'b0; array_mode_2_2 <= 1'b0; array_mode_2_3 <= 1'b0;
      array_mode_3_0 <= 1'b0; array_mode_3_1 <= 1'b0; array_mode_3_2 <= 1'b0; array_mode_3_3 <= 1'b0;
    end
    else if (state_is_mul_store) begin
      case (store_cnt)
        0: begin
          array_en_up_0_0   <= 1;
          array_en_up_0_1   <= 1;
          array_en_up_0_2   <= 1;
          array_en_up_0_3   <= 1;

          array_data_up_0_0 <= matrix_A_reg[3];
          array_data_up_0_1 <= matrix_A_reg[7];
          array_data_up_0_2 <= matrix_A_reg[11];
          array_data_up_0_3 <= matrix_A_reg[15];

          array_mode_0_0 <= 1; array_mode_0_1 <= 1; array_mode_0_2 <= 1; array_mode_0_3 <= 1;
          array_mode_1_0 <= 1; array_mode_1_1 <= 1; array_mode_1_2 <= 1; array_mode_1_3 <= 1;
          array_mode_2_0 <= 1; array_mode_2_1 <= 1; array_mode_2_2 <= 1; array_mode_2_3 <= 1;
          array_mode_3_0 <= 1; array_mode_3_1 <= 1; array_mode_3_2 <= 1; array_mode_3_3 <= 1;
        end

        1: begin
          
          array_data_up_0_0 <= matrix_A_reg[2];
          array_data_up_0_1 <= matrix_A_reg[6];
          array_data_up_0_2 <= matrix_A_reg[10];
          array_data_up_0_3 <= matrix_A_reg[14];
        end

        2: begin
          array_data_up_0_0 <= matrix_A_reg[1];
          array_data_up_0_1 <= matrix_A_reg[5];
          array_data_up_0_2 <= matrix_A_reg[9];
          array_data_up_0_3 <= matrix_A_reg[13];
        end

        3: begin
          array_data_up_0_0 <= matrix_A_reg[0];
          array_data_up_0_1 <= matrix_A_reg[4];
          array_data_up_0_2 <= matrix_A_reg[8];
          array_data_up_0_3 <= matrix_A_reg[12];
        end

        default: begin
          array_en_up_0_0   <= 0; array_en_up_0_1   <= 0; array_en_up_0_2   <= 0; array_en_up_0_3   <= 0;
          array_data_up_0_0 <= 0; array_data_up_0_1 <= 0; array_data_up_0_2 <= 0; array_data_up_0_3 <= 0;
          array_mode_0_0 <= 0; array_mode_0_1 <= 0; array_mode_0_2 <= 0; array_mode_0_3 <= 0;
          array_mode_1_0 <= 0; array_mode_1_1 <= 0; array_mode_1_2 <= 0; array_mode_1_3 <= 0;
          array_mode_2_0 <= 0; array_mode_2_1 <= 0; array_mode_2_2 <= 0; array_mode_2_3 <= 0;
          array_mode_3_0 <= 0; array_mode_3_1 <= 0; array_mode_3_2 <= 0; array_mode_3_3 <= 0;
        end
      endcase
    end
  end

  //////////// 6. custom3_mul_cals
  localparam cals_full_cycles = 18;
  
  integer mul_cals_cnt;
  wire mul_cals_cnt_done    = (mul_cals_cnt == cals_full_cycles);
  wire mul_cals_icb_rsp_hs  = state_is_mul_cals;
  wire mul_cals_cnt_incr    = mul_cals_icb_rsp_hs & ~mul_cals_cnt_done;
  assign mul_cals_done      = mul_cals_icb_rsp_hs & mul_cals_cnt_done;

  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      mul_cals_cnt <= 0;
    else if (mul_cals_done)
      mul_cals_cnt <= 0;
    else if (mul_cals_cnt_incr)
      mul_cals_cnt <= mul_cals_cnt + 1;
    else
      mul_cals_cnt <= mul_cals_cnt;
  end

  localparam matrix_size_C = 12;
  reg signed [DATA_WIDTH-1:0] mul_cals_reg [0:matrix_size_C-1];
  
  integer mul_cals_cmd_cnt;
  wire nice_icb_cmd_hsked;

  wire mul_cals_store        = mul_cals_cnt >= 6;
  wire mul_cals_cmd_cnt_done = (mul_cals_cmd_cnt == matrix_size_C);
  wire mul_cals_cmd_hsked    = state_is_mul_cals & nice_icb_cmd_hsked;
  wire mul_cals_cmd_cnt_incr = mul_cals_cmd_hsked & ~mul_cals_cmd_cnt_done;

  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      mul_cals_cmd_cnt <= 0;
    else if (mul_cals_store) begin 
      if (mul_cals_cmd_cnt_done)
        mul_cals_cmd_cnt <= 0;
      else if (mul_cals_cmd_cnt_incr)
        mul_cals_cmd_cnt <= mul_cals_cmd_cnt + 1;
      else
        mul_cals_cmd_cnt <= mul_cals_cmd_cnt;
    end
  end

  // valid signals
  wire nice_rsp_valid_mul_cals     = state_is_mul_cals & mul_cals_cnt_done & nice_icb_rsp_valid;
  wire nice_icb_cmd_valid_mul_cals = state_is_mul_cals & (mul_cals_cmd_cnt < matrix_size_C) & mul_cals_store;

  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      array_en_left_0_0   <= 1'b0; 
      array_en_left_1_0   <= 1'b0; 
      array_en_left_2_0   <= 1'b0; 
      array_en_left_3_0   <= 1'b0; 
      array_data_left_0_0 <= {DATA_WIDTH{1'b0}};
      array_data_left_1_0 <= {DATA_WIDTH{1'b0}};
      array_data_left_2_0 <= {DATA_WIDTH{1'b0}};
      array_data_left_3_0 <= {DATA_WIDTH{1'b0}};
      for (i = 0; i < matrix_size_C; i = i + 1)
        mul_cals_reg[i]   <= {DATA_WIDTH{1'b0}};
    end else if (state_is_mul_cals) begin
      case (mul_cals_cnt)
        0: begin
          array_en_left_0_0   <= 1;
          array_en_left_1_0   <= 1;
          array_en_left_2_0   <= 1;
          array_en_left_3_0   <= 1;
          array_data_left_0_0 <= matrix_B_reg[0];
          array_data_left_1_0 <= 0;
          array_data_left_2_0 <= 0;
          array_data_left_3_0 <= 0;
        end
        1: begin
          array_data_left_0_0 <= matrix_B_reg[1];
          array_data_left_1_0 <= matrix_B_reg[3];
          array_data_left_2_0 <= 0;
          array_data_left_3_0 <= 0;
        end
        2: begin
          array_data_left_0_0 <= matrix_B_reg[2];
          array_data_left_1_0 <= matrix_B_reg[4];
          array_data_left_2_0 <= matrix_B_reg[6];
          array_data_left_3_0 <= 0;
        end
        3: begin
          array_data_left_0_0 <= 0;
          array_data_left_1_0 <= matrix_B_reg[5];
          array_data_left_2_0 <= matrix_B_reg[7];
          array_data_left_3_0 <= matrix_B_reg[9];
        end
        4: begin
          array_data_left_0_0 <= 0;
          array_data_left_1_0 <= 0;
          array_data_left_2_0 <= matrix_B_reg[8];
          array_data_left_3_0 <= matrix_B_reg[10];
        end
        5: begin
          array_data_left_0_0 <= 0;
          array_data_left_1_0 <= 0;
          array_data_left_2_0 <= 0;
          array_data_left_3_0 <= matrix_B_reg[11];
          mul_cals_reg[0]  <= array_data_down_3_0;
        end
        6: begin
          array_en_left_0_0   <= 0;
          array_en_left_1_0   <= 0;
          array_en_left_2_0   <= 0;
          array_en_left_3_0   <= 0;
          array_data_left_0_0 <= 0;
          array_data_left_1_0 <= 0;
          array_data_left_2_0 <= 0;
          array_data_left_3_0 <= 0;
          mul_cals_reg[1]  <= array_data_down_3_0;
          mul_cals_reg[3]  <= array_data_down_3_1;
        end
        7: begin
          mul_cals_reg[2]  <= array_data_down_3_0;
          mul_cals_reg[4]  <= array_data_down_3_1;
          mul_cals_reg[6]  <= array_data_down_3_2;
        end
        8: begin
          mul_cals_reg[5]  <= array_data_down_3_1;
          mul_cals_reg[7]  <= array_data_down_3_2;
          mul_cals_reg[9]  <= array_data_down_3_3;
        end
        9: begin
          mul_cals_reg[8]  <= array_data_down_3_2;
          mul_cals_reg[10] <= array_data_down_3_3;
        end
        10: begin
          mul_cals_reg[11] <= array_data_down_3_3;
        end
        default: begin
          array_en_left_0_0   <= 1'b0; 
          array_en_left_1_0   <= 1'b0; 
          array_en_left_2_0   <= 1'b0; 
          array_en_left_3_0   <= 1'b0; 
          array_data_left_0_0 <= {DATA_WIDTH{1'b0}};
          array_data_left_1_0 <= {DATA_WIDTH{1'b0}};
          array_data_left_2_0 <= {DATA_WIDTH{1'b0}};
          array_data_left_3_0 <= {DATA_WIDTH{1'b0}};
        end
      endcase
    end
  end

  reg [`E203_XLEN-1:0] mul_cals_rs1_reg;

  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      mul_cals_rs1_reg <= 0;
    else if (state_is_idle & custom3_mul_cals)
      mul_cals_rs1_reg <= nice_req_rs1;
  end
  

  //////////// mem aacess addr management
  // The memory address accumulator is updated when any of the following operations
  // (custom3_lbuf, custom3_sbuf, custom3_rowsum) are enabled.
  // When in IDLE state, the accumulator starts with the base address from nice_req_rs1;
  // otherwise, it increments by 4 (word size) each time a memory command handshake occurs.

  reg [`E203_XLEN-1:0] maddr_acc_r;  // Memory address accumulator register

  // Generate the command handshake signal
  assign nice_icb_cmd_hsked = nice_icb_cmd_valid & nice_icb_cmd_ready;

  // Determine individual enable signals for each operation
  wire mul_loada_maddr_ena  = (state_is_idle & custom3_mul_loada  & nice_icb_cmd_hsked) | (state_is_mul_loada  & nice_icb_cmd_hsked);
  wire mul_loadb_maddr_ena  = (state_is_idle & custom3_mul_loadb  & nice_icb_cmd_hsked) | (state_is_mul_loadb  & nice_icb_cmd_hsked);
  wire mul_cals_maddr_ena   = (state_is_mul_cals & mul_cals_store);

  // Combine the enable signals for the memory address update
  wire maddr_ena = mul_loada_maddr_ena | mul_loadb_maddr_ena | mul_cals_maddr_ena;

  // When in IDLE state, use the base address from nice_req_rs1; otherwise, use the current accumulator value.
  wire maddr_ena_idle = (maddr_ena & state_is_idle) | (mul_cals_cnt == 6);
  wire [`E203_XLEN-1:0] maddr_acc_op1 = maddr_ena_idle ? ((mul_cals_cnt == 6) ? mul_cals_rs1_reg : nice_req_rs1) : maddr_acc_r;

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
  assign nice_rsp_valid = nice_rsp_valid_mul_loada | nice_rsp_valid_mul_loadb | nice_rsp_valid_mul_cals;

  // When in the ROWSUM state, the response data is the accumulated row sum;
  // in other states, it is typically zero or unused here.
  assign nice_rsp_rdat  = {`E203_XLEN{1'b0}}; //{`E203_XLEN{state_is_rowsum}} & rowsum_res;

  // Indicate a memory access bus error if a valid memory response indicates an error.
  // (Optionally, an illegal-instruction check can also be included if needed.)
  assign nice_rsp_err   = (nice_icb_rsp_hsked & nice_icb_rsp_err);


  ////////////////////////////////////////////////////////////
  // Memory LSU (Load/Store Unit) for NICE operations
  ////////////////////////////////////////////////////////////

  // Always ready to accept memory responses
  assign nice_icb_rsp_ready = 1'b1;

  // SBUF uses sbuf_cmd_cnt to index into rowbuf when writing to memory
  wire [5:0] cals_idx = mul_cals_cmd_cnt;

  // Generate the memory command valid signal. It is asserted if:
  // 1. In IDLE with a valid request that needs memory (custom_mem_op),
  // 2. LBUF logic indicates a need to read more data from memory,
  // 3. SBUF logic indicates a need to write data to memory,
  // 4. ROWSUM logic indicates a need to read additional data from memory.
  assign nice_icb_cmd_valid =
         (state_is_idle & nice_req_valid & custom_mem_op)
         | nice_icb_cmd_valid_mul_loada
         | nice_icb_cmd_valid_mul_loadb
         | nice_icb_cmd_valid_mul_cals;

  // Select the memory address. If in IDLE and about to start a memory operation,
  // use the base address from nice_req_rs1; otherwise, use the accumulated address.
  assign nice_icb_cmd_addr = (state_is_idle & custom_mem_op) ? nice_req_rs1 : 
                             (mul_cals_cnt == 6) ? mul_cals_rs1_reg :
                             maddr_acc_r;

  // Determine whether the operation is a read or write:
  // - In IDLE, if the next operation is either LBUF or ROWSUM, use read.
  // - In SBUF state, use write.
  // - Otherwise, default to read.
  assign nice_icb_cmd_read = (state_is_idle & custom_mem_op)
         ? (custom3_mul_loada | custom3_mul_loadb)
         : ((mul_cals_maddr_ena) ? 1'b0 : 1'b1);

  // Select the write data when in SBUF state or about to start SBUF from IDLE.
  assign nice_icb_cmd_wdata = mul_cals_maddr_ena ? mul_cals_reg[cals_idx] :
                              {`E203_XLEN{1'b0}};

  // For simplicity, the write mask is not assigned in this design. If needed,
  // it can be set to select specific byte lanes (e.g., 4'b1111 for a full word).
  // assign nice_icb_cmd_wmask = {`sirv_XLEN_MW{custom3_sbuf}} & 4'b1111;

  // The transaction size is fixed at word (2'b10).
  assign nice_icb_cmd_size = 2'b10;

  // Assert 'nice_mem_holdup' when in any multi-cycle memory state
  // (LBUF, SBUF, or ROWSUM) to stall the core if necessary.
  assign nice_mem_holdup = state_is_mul_loada | state_is_mul_loadb | state_is_mul_cals;


  ////////////////////////////////////////////////////////////
  // NICE Active Signal
  ////////////////////////////////////////////////////////////
  // The NICE core is active if there is a request in IDLE or if the FSM is
  // in any of the operational states (LBUF, SBUF, ROWSUM).
  assign nice_active = state_is_idle ? nice_req_valid : 1'b1;

  
endmodule
`endif//}
