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
  wire custom3_load_input = custom3 && (func3 == 3'b010) && (func7 == 7'b0001100);
  wire custom3_start      = custom3 && (func3 == 3'b010) && (func7 == 7'b0001101);

  ////////////////////////////////////////////////////////////
  //  multi-cyc op
  ////////////////////////////////////////////////////////////
  wire custom_multi_cyc_op = custom3_load_conv1 | custom3_load_input | custom3_start;
  // need access memory
  wire custom_mem_op       = custom3_load_conv1 | custom3_load_input;

  ////////////////////////////////////////////////////////////
  // NICE FSM
  ////////////////////////////////////////////////////////////
  localparam IDLE       = 4'd0;
  localparam LOAD_CONV1 = 4'd1;
  localparam LOAD_INPUT = 4'd2;
  localparam MOVE_CONV1 = 4'd3;
  localparam START_CONV = 4'd4;

  // FSM state register
  integer state;

  wire state_is_idle       = (state == IDLE);
  wire state_is_load_conv1 = (state == LOAD_CONV1);
  wire state_is_load_input = (state == LOAD_INPUT);
  wire state_is_move_conv1 = (state == MOVE_CONV1);
  wire state_is_start_conv = (state == START_CONV);

  // handshake success signals
  wire nice_req_hsked;
  wire nice_icb_rsp_hsked;
  wire nice_rsp_hsked;

  // finish signals
  wire load_conv1_done;
  wire load_input_done;
  wire move_conv1_done;
  wire start_conv_done;

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
            if (custom3_load_conv1)
              state <= LOAD_CONV1;
            else if (custom3_load_input)
              state <= LOAD_INPUT;
            else if (custom3_start)
              state <= MOVE_CONV1;
            else
              state <= IDLE;
          end
          else
          begin
            state <= IDLE;
          end
        end
        
        LOAD_CONV1:
        begin
          if (load_conv1_done)
            state <= IDLE;
          else
            state <= LOAD_CONV1;
        end

        LOAD_INPUT:
        begin
          if (load_input_done)
            state <= IDLE;
          else
            state <= LOAD_INPUT;
        end

        MOVE_CONV1:
        begin
          if (move_conv1_done)
            state <= START_CONV;
          else
            state <= MOVE_CONV1;
        end

        START_CONV:
        begin
          if (start_conv_done)
            state <= IDLE;
          else
            state <= START_CONV;
        end

        default:
          state <= IDLE;
      endcase
    end
  end



  ////////////////////////////////////////////////////////////
  // instr EXU
  ////////////////////////////////////////////////////////////
  //////////// 1. custom3_load_conv1
  integer i, j, k;

  localparam conv1_num   = 5;
  localparam conv1_width = 3;
  localparam conv1_rc    = conv1_width * conv1_width;
  localparam conv1_size  = conv1_num * conv1_rc;

  integer load_conv1_cnt;

  wire load_conv1_cnt_done    = (load_conv1_cnt == conv1_size);
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
  wire nice_icb_cmd_valid_load_conv1 = state_is_load_conv1 & (load_conv1_cnt < conv1_size);


  // conv1 buffer index
  reg [$clog2(conv1_num)-1:0]  conv1_num_idx;
  reg [$clog2(conv1_rc) -1:0]  conv1_rc_idx;

  // conv1 buffer index accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      conv1_num_idx <= 0;
      conv1_rc_idx  <= 0;
    end
    else if (load_conv1_icb_rsp_hs) begin
      if (conv1_rc_idx == conv1_rc - 1) begin
        conv1_rc_idx <= 0;
        if (conv1_num_idx == conv1_num_idx - 1) begin
          conv1_num_idx <= 0;
        end
        else begin
          conv1_num_idx <= conv1_num_idx + 1;
        end
      end 
      else begin
        conv1_rc_idx <= conv1_rc_idx + 1;
      end
    end
  end


  // conv1 buffer
  reg signed [`E203_XLEN-1:0] conv1_reg [conv1_num][conv1_rc];

  // conv1 buffer data storage
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      conv1_reg[i][j] <= '{default: '0};
    end 
    else if (load_conv1_cnt_incr) begin
      conv1_reg[conv1_num_idx][conv1_rc_idx] <= $signed(nice_icb_rsp_rdata);
    end
  end


  //////////// 2. custom3_load_input
  localparam input_width  = 14;
  localparam input_size   = input_width * input_width;

  integer load_input_cnt;

  wire load_input_cnt_done    = (load_input_cnt == input_size);
  wire load_input_icb_rsp_hs  = state_is_load_input   & nice_icb_rsp_hsked;
  wire load_input_cnt_incr    = load_input_icb_rsp_hs & ~load_input_cnt_done;
  assign load_input_done      = load_input_icb_rsp_hs & load_input_cnt_done;

  // load_input_cnt accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      load_input_cnt <= 0;
    else 
    if (load_conv1_done)
      load_input_cnt <= 0;
    else if (load_input_cnt_incr)
      load_input_cnt <= load_input_cnt + 1;
    else
      load_input_cnt <= load_input_cnt;
  end

  // valid signals
  wire nice_rsp_valid_load_input     = state_is_load_input & load_input_cnt_done & nice_icb_rsp_valid;
  wire nice_icb_cmd_valid_load_input = state_is_load_input & (load_input_cnt < input_size);


  // input buffer index
  reg [$clog2(input_width)-1:0] input_row_idx;
  reg [$clog2(input_width)-1:0] input_col_idx;

  // input buffer index accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      input_row_idx <= 0;
      input_col_idx <= 0;
    end
    else if (load_input_icb_rsp_hs) begin
      if (input_col_idx == input_width - 1) begin
        input_col_idx <= 0;
        if (input_row_idx == input_width - 1) begin
          input_row_idx <= 0;
        end 
        else begin
          input_row_idx <= input_row_idx + 1;
        end
      end 
      else begin
        input_col_idx <= input_col_idx + 1;
      end
    end
  end


  // input buffer
  reg signed [`E203_XLEN-1:0] input_reg [input_width][input_width];

  // input buffer data storage
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      input_reg <= '{default: '0};
    end 
    else if (load_input_cnt_incr) begin
      input_reg[input_row_idx][input_col_idx] <= $signed(nice_icb_rsp_rdata);
    end 
  end


  ////////////////////////////////////////////////////////////
  // SYSTOLIC ARRAY 
  ////////////////////////////////////////////////////////////
  parameter int DATA_WIDTH    = 32;
  parameter int SA_ROWS       = 10;
  parameter int SA_COLS       = 5;

  logic  [SA_ROWS-1:0]        sa_en_left;
  logic  [DATA_WIDTH-1:0]     sa_data_left [SA_ROWS];
  logic  [SA_COLS-1:0]        sa_en_up;
  logic  [DATA_WIDTH-1:0]     sa_data_up   [SA_COLS];
  logic  [SA_COLS-1:0]        sa_en_down;
  logic  [DATA_WIDTH-1:0]     sa_data_down [SA_COLS];
  logic                       sa_mode      [SA_ROWS][SA_COLS];

  systolic_array_10_5 #(
    .DATA_WIDTH(DATA_WIDTH),
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

  //////////// 3. move_conv1
  integer move_conv1_cnt;

  wire move_conv1_cnt_done    = (move_conv1_cnt == SA_ROWS);
  assign move_conv1_done      = move_conv1_cnt_done;
  
  // move_conv1_cnt accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      move_conv1_cnt <= 0;
    else 
    if (state_is_move_conv1) begin
      if (move_conv1_cnt_done)
        move_conv1_cnt <= 0;
      else
        move_conv1_cnt <= move_conv1_cnt + 1;
    end
  end


  // move conv1 kernels to systolic array
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if(!nice_rst_n) begin
      sa_en_up    <= '0;
      sa_data_up  <= '{default: '0};
      sa_mode     <= '{default: '0};
    end
    else if (state_is_move_conv1) begin
      if (move_conv1_cnt == 0) begin
        for (i = 0; i < SA_ROWS; i = i + 1) begin
          for (j = 0; j < SA_COLS; j = j + 1) begin
            sa_mode[i][j] <= 1'b1;
          end
        end
        sa_en_up <= {SA_COLS{1'b1}};
        for (i = 0; i < SA_COLS; i = i + 1) begin
          sa_data_up[i] <= conv1_reg[i][conv1_rc-1];
        end
      end
      else if ((move_conv1_cnt >= 1) && (move_conv1_cnt <= SA_ROWS-2)) begin
        for (i = 0; i < SA_COLS; i = i + 1) begin
          sa_data_up[i] <= conv1_reg[i][conv1_rc-1-move_conv1_cnt];
        end
      end
      else if (move_conv1_cnt == SA_ROWS-1) begin
        for (i = 0; i < SA_COLS; i = i + 1) begin
          sa_data_up[i] <= '0;
        end
      end
      else begin
        sa_en_up <= '0;
        for (i = 0; i < SA_COLS; i = i + 1) begin
          sa_data_up[i] <= '0;
        end
        for (i = 0; i < SA_ROWS; i = i + 1) begin
          for (j = 0; j < SA_COLS; j = j + 1) begin
            sa_mode[i][j] <= 1'b0;
          end
        end
      end
    end
  end


  //////////// 4. conv_start
  localparam output_width = input_width - conv1_width + 1;
  localparam output_size  = output_width * output_width;
  localparam conv_start_cycles = output_size * conv1_num + SA_ROWS + 2;

  integer conv_start_cnt;
  wire conv_start_cnt_done    = (conv_start_cnt == conv_start_cycles);
  wire conv_start_icb_rsp_hs  = state_is_start_conv;
  wire conv_start_cnt_incr    = conv_start_icb_rsp_hs & ~conv_start_cnt_done;
  assign start_conv_done      = conv_start_icb_rsp_hs & conv_start_cnt_done;

  // conv_start_cnt accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      conv_start_cnt <= 0;
    else 
    if (start_conv_done)
      conv_start_cnt <= 0;
    else if (conv_start_cnt_incr)
      conv_start_cnt <= conv_start_cnt + 1;
    else
      conv_start_cnt <= conv_start_cnt;
  end


  integer conv_start_cmd_cnt;

  wire nice_icb_cmd_hsked;

  wire conv_start_cmd_store        = conv_start_cnt >= (SA_ROWS + 2);
  wire conv_start_cmd_store_first  = conv_start_cnt == (SA_ROWS + 2);
  wire conv_start_cmd_cnt_done     = (conv_start_cmd_cnt == output_size);

  // valid signals
  wire nice_rsp_valid_start_conv     = state_is_start_conv & conv_start_cnt_done & nice_icb_rsp_valid;
  wire nice_icb_cmd_valid_start_conv = state_is_start_conv & (conv_start_cnt < conv_start_cycles) & conv_start_cmd_store;

  reg [$clog2(conv1_num)   -1:0]  output_cmd_num_idx;
  reg [$clog2(output_width)-1:0]  output_cmd_row_idx;
  reg [$clog2(output_width)-1:0]  output_cmd_col_idx;

  // output_cmd_idx accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      output_cmd_num_idx <= '0;
      output_cmd_row_idx <= '0;
      output_cmd_col_idx <= '0;
    end 
    else if (conv_start_cmd_store) begin // >=11
      if (output_cmd_col_idx == output_width - 1) begin
        output_cmd_col_idx <= 0;
        if (output_cmd_row_idx == output_width - 1) begin
          output_cmd_row_idx <= 0;
          if (output_cmd_num_idx == conv1_num - 1) begin
            output_cmd_num_idx <= 0;
          end
          else begin
            output_cmd_num_idx <= output_cmd_num_idx + 1;
          end
        end
        else begin
          output_cmd_row_idx <= output_cmd_row_idx + 1;
        end
      end 
      else begin
        output_cmd_col_idx <= output_cmd_col_idx + 1;
      end
    end
  end


  reg [$clog2(output_width)-1:0]  output_row_idx[conv1_rc];
  reg [$clog2(output_width)-1:0]  output_col_idx[conv1_rc];

  // input matrix move to SA index accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      output_row_idx <= '{default: '0};
      output_col_idx <= '{default: '0};
    end 
    else if (conv_start_cnt) begin // >=1
      for (i = 0; i < conv1_rc; i = i + 1) begin
        if (output_col_idx[i] == output_width - 1) begin
          output_col_idx[i] <= 0;
          if (output_row_idx[i] == output_width - 1)
              output_row_idx[i] <= 0;
          else
            output_row_idx[i] <= output_row_idx[i] + 1;
        end 
        else begin
          if (i <= conv_start_cnt-1)
            output_col_idx[i] <= output_col_idx[i] + 1;
        end
      end
    end
  end


  reg [$clog2(output_width)-1:0]  output_store_row_idx[conv1_num];
  reg [$clog2(output_width)-1:0]  output_store_col_idx[conv1_num];

  // output buffer index accumulation
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      output_store_row_idx <= '{default: '0};
      output_store_col_idx <= '{default: '0};
    end 
    else if (conv_start_cnt >= (SA_ROWS + 1)) begin // >=11
      for (i = 0; i < conv1_num; i = i + 1) begin
        if (output_store_col_idx[i] == output_width - 1) begin
          output_store_col_idx[i] <= 0;
          if (output_store_row_idx[i] == output_width - 1)
            output_store_row_idx[i] <= 0;
          else
            output_store_row_idx[i] <= output_store_row_idx[i] + 1;
        end 
        else begin
          if (i < (conv_start_cnt - (conv1_rc + 1)))
            output_store_col_idx[i] <= output_store_col_idx[i] + 1;
        end
      end
    end
  end


  localparam int output_row_offset[conv1_rc] = '{0, 0, 0, 1, 1, 1, 2, 2, 2};
  localparam int output_col_offset[conv1_rc] = '{0, 1, 2, 0, 1, 2, 0, 1, 2};

  reg signed [`E203_XLEN-1:0]  output_reg[conv1_num][output_width][output_width];

  // move input data to systolic array, and store output data
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      sa_en_left   <= '0;
      sa_data_left <= '{default: '0};
      output_reg   <= '{default: '0};
    end
    else if (state_is_start_conv & (conv_start_cnt > 0)) begin
      if (conv_start_cnt == 1) begin // 1
        sa_en_left <= {SA_ROWS{1'b1}};
        sa_data_left[1] <= input_reg[output_row_idx[0]][output_col_idx[0]];
      end 
      else if ((conv_start_cnt > 1) && (conv_start_cnt <= conv1_rc)) begin // 2-9
        for (i = 0; i < conv_start_cnt; i = i + 1)
          sa_data_left[i+1] <= input_reg[output_row_idx[i]+output_row_offset[i]][output_col_idx[i]+output_col_offset[i]];
      end 
      else if (conv_start_cnt == (conv1_rc + 1)) begin // 10
        for (i = 0; i < conv1_rc; i = i + 1)
          sa_data_left[i+1] <= input_reg[output_row_idx[i]+output_row_offset[i]][output_col_idx[i]+output_col_offset[i]];
      end
      else if ((conv_start_cnt > (conv1_rc + 1)) && (conv_start_cnt <= (conv1_rc + 1 + conv1_num))) begin // 11-15
        for (i = 0; i < conv1_rc; i = i + 1)
          sa_data_left[i+1] <= input_reg[output_row_idx[i]+output_row_offset[i]][output_col_idx[i]+output_col_offset[i]];
        for (i = 0; i < (conv_start_cnt - (conv1_rc + 1)); i = i + 1) 
          output_reg[i][output_store_row_idx[i]][output_store_col_idx[i]] <= sa_data_down[i];
      end
      else if ((conv_start_cnt > (conv1_rc + 1 + conv1_num)) && (conv_start_cnt <= output_size)) begin // 16-144
        for (i = 0; i < conv1_rc; i = i + 1)
          sa_data_left[i+1] <= input_reg[output_row_idx[i]+output_row_offset[i]][output_col_idx[i]+output_col_offset[i]];
        for (i = 0; i < conv1_num; i = i + 1) 
          output_reg[i][output_store_row_idx[i]][output_store_col_idx[i]] <= sa_data_down[i];
      end
      else if ((conv_start_cnt > output_size) && (conv_start_cnt <= (output_size + conv1_rc))) begin // 145-153
        for (i = 0; i < conv1_rc; i = i + 1) begin
          if (i >= (conv_start_cnt - output_size))
            sa_data_left[i+1] <= input_reg[output_row_idx[i]+output_row_offset[i]][output_col_idx[i]+output_col_offset[i]];
          else
            sa_data_left[i+1] <= '0;
        end
        for (i = 0; i < conv1_num; i = i + 1) 
          output_reg[i][output_store_row_idx[i]][output_store_col_idx[i]] <= sa_data_down[i];
        if (conv_start_cnt == (output_size + conv1_rc))
          sa_en_left <= '0;
      end
      else if ((conv_start_cnt > (output_size + conv1_rc)) && (conv_start_cnt <= (output_size + conv1_rc + SA_COLS))) begin // 154-158
        for (i = 0; i < conv1_num; i = i + 1) begin
          if (i >= (conv_start_cnt - (output_size + conv1_rc + 1)))
            output_reg[i][output_store_row_idx[i]][output_store_col_idx[i]] <= sa_data_down[i];
        end
      end
    end
  end


  reg [`E203_XLEN-1:0] start_conv_rs1_reg;

  // store rs1
  always @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n)
      start_conv_rs1_reg <= 0;
    else if (state_is_idle & custom3_start)
      start_conv_rs1_reg <= nice_req_rs1;
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
  wire load_conv1_maddr_ena = (state_is_idle & custom3_load_conv1 & nice_icb_cmd_hsked) | (state_is_load_conv1 & nice_icb_cmd_hsked);
  wire load_input_maddr_ena = (state_is_idle & custom3_load_input & nice_icb_cmd_hsked) | (state_is_load_input & nice_icb_cmd_hsked);
  wire conv_start_maddr_ena = (state_is_start_conv & conv_start_cmd_store);

  // Combine the enable signals for the memory address update
  wire maddr_ena = load_conv1_maddr_ena | load_input_maddr_ena | conv_start_maddr_ena;

  // When in IDLE state, use the base address from nice_req_rs1; otherwise, use the current accumulator value.
  wire maddr_ena_idle = (maddr_ena & state_is_idle) | conv_start_cmd_store_first;
  wire [`E203_XLEN-1:0] maddr_acc_op1 = maddr_ena_idle ? 
                                        (conv_start_cmd_store_first ? start_conv_rs1_reg : nice_req_rs1) : 
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
  assign nice_rsp_valid = nice_rsp_valid_load_conv1 | nice_rsp_valid_load_input | nice_rsp_valid_start_conv;

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

  // Generate the memory command valid signal.
  assign nice_icb_cmd_valid =
         (state_is_idle & nice_req_valid & custom_mem_op)
         | nice_icb_cmd_valid_load_conv1
         | nice_icb_cmd_valid_load_input
         | nice_icb_cmd_valid_start_conv;

  // Select the memory address. If in IDLE and about to start a memory operation,
  // use the base address from nice_req_rs1; otherwise, use the accumulated address.
  assign nice_icb_cmd_addr = (state_is_idle & custom_mem_op) ? nice_req_rs1 : 
                             (conv_start_cmd_store_first) ? start_conv_rs1_reg :
                             maddr_acc_r;

  // Determine whether the operation is a read or write
  assign nice_icb_cmd_read = (state_is_idle & custom_mem_op)
         ? (custom3_load_conv1 | custom3_load_input)
         : ((conv_start_maddr_ena) ? 1'b0 : 1'b1);

  // Select the write data when in SBUF state or about to start SBUF from IDLE.
  assign nice_icb_cmd_wdata = conv_start_maddr_ena ? output_reg[output_cmd_num_idx][output_cmd_row_idx][output_cmd_col_idx] :
                              {`E203_XLEN{1'b0}};

  // The transaction size is fixed at word (2'b10).
  assign nice_icb_cmd_size = 2'b10;

  // Assert 'nice_mem_holdup' when in any multi-cycle memory state
  assign nice_mem_holdup = state_is_load_conv1 | state_is_load_input | state_is_start_conv;


  ////////////////////////////////////////////////////////////
  // NICE Active Signal
  ////////////////////////////////////////////////////////////
  assign nice_active = state_is_idle ? nice_req_valid : 1'b1;

  
endmodule
`endif//}
