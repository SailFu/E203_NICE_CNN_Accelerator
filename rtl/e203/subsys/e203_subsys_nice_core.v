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
    input                         nice_rst_n	          ,
    output                        nice_active	      ,
    output                        nice_mem_holdup	  ,
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
    output                        nice_rsp_err    	  ,
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
  wire custom3_lbuf   = custom3 && (func3 == 3'b010) && (func7 == 7'b0000001);
  wire custom3_sbuf   = custom3 && (func3 == 3'b010) && (func7 == 7'b0000010);
  wire custom3_rowsum = custom3 && (func3 == 3'b110) && (func7 == 7'b0000110);

  
   ////////////////////////////////////////////////////////////
   //  multi-cyc op 
   ////////////////////////////////////////////////////////////
   wire custom_multi_cyc_op = custom3_lbuf | custom3_sbuf | custom3_rowsum;
   // need access memory
   wire custom_mem_op = custom3_lbuf | custom3_sbuf | custom3_rowsum;
 
   ////////////////////////////////////////////////////////////
   // NICE FSM 
   ////////////////////////////////////////////////////////////
   localparam NICE_FSM_WIDTH = 2;
   localparam IDLE     = 2'd0;
   localparam LBUF     = 2'd1;
   localparam SBUF     = 2'd2;
   localparam ROWSUM   = 2'd3;

   // FSM state register
   reg [NICE_FSM_WIDTH-1:0] state;

   wire state_is_idle     = (state == IDLE); 
   wire state_is_lbuf     = (state == LBUF); 
   wire state_is_sbuf     = (state == SBUF); 
   wire state_is_rowsum   = (state == ROWSUM); 
   
   // handshake success signals
   wire nice_req_hsked;
   wire nice_icb_rsp_hsked; 
   wire nice_rsp_hsked;

   // finish signals
   wire lbuf_icb_rsp_hsked_last;
   wire sbuf_icb_rsp_hsked_last;
   wire rowsum_done;
   
   // FSM state update using behavioral description
   always @(posedge nice_clk or negedge nice_rst_n) begin
     if (!nice_rst_n)
       state <= IDLE;  // Reset state to IDLE
     else begin
       case (state)
         // In IDLE, if a valid request occurs and the instruction is one of the supported custom3 ops,
         // transition to the corresponding state.
         IDLE: begin
           if (nice_req_hsked && (custom3_lbuf || custom3_sbuf || custom3_rowsum)) begin
             if (custom3_lbuf)
               state <= LBUF;
             else if (custom3_sbuf)
               state <= SBUF;
             else if (custom3_rowsum)
               state <= ROWSUM;
           end
           else begin
             state <= IDLE;
           end
         end
   
         // In LBUF, remain until the last ICB response handshake occurs.
         LBUF: begin
           if (lbuf_icb_rsp_hsked_last)
             state <= IDLE;
           else
             state <= LBUF;
         end
   
         // In SBUF, remain until the last ICB response handshake occurs.
         SBUF: begin
           if (sbuf_icb_rsp_hsked_last)
             state <= IDLE;
           else
             state <= SBUF;
         end
   
         // In ROWSUM, remain until the row sum operation is completed.
         ROWSUM: begin
           if (rowsum_done)
             state <= IDLE;
           else
             state <= ROWSUM;
         end
   
         default: state <= IDLE;
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
   always @(posedge nice_clk or negedge nice_rst_n) begin
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
   always @(posedge nice_clk or negedge nice_rst_n) begin
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
   always @(posedge nice_clk or negedge nice_rst_n) begin
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
   wire [ROWBUF_IDX_W-1:0] rowbuf_cnt_r; 
   wire [ROWBUF_IDX_W-1:0] rowbuf_cnt_nxt; 
   wire rowbuf_cnt_clr;
   wire rowbuf_cnt_incr;
   wire rowbuf_cnt_ena;
   wire rowbuf_cnt_last;
   wire rowbuf_icb_rsp_hsked;
   wire rowbuf_rsp_hsked;
   wire nice_rsp_valid_rowsum;

   assign rowbuf_rsp_hsked = nice_rsp_valid_rowsum & nice_rsp_ready;
   assign rowbuf_icb_rsp_hsked = state_is_rowsum & nice_icb_rsp_hsked;
   assign rowbuf_cnt_last = (rowbuf_cnt_r == clonum);
   assign rowbuf_cnt_clr = rowbuf_icb_rsp_hsked & rowbuf_cnt_last;
   assign rowbuf_cnt_incr = rowbuf_icb_rsp_hsked & ~rowbuf_cnt_last;
   assign rowbuf_cnt_ena = rowbuf_cnt_clr | rowbuf_cnt_incr;
   assign rowbuf_cnt_nxt =   ({ROWBUF_IDX_W{rowbuf_cnt_clr }} & {ROWBUF_IDX_W{1'b0}})
                           | ({ROWBUF_IDX_W{rowbuf_cnt_incr}} & (rowbuf_cnt_r + 1'b1))
                           ;
   //assign nice_icb_cmd_valid_rowbuf =   (state_is_idle & custom3_rowsum)
   //                                  | (state_is_rowsum & (rowbuf_cnt_r <= clonum) & (clonum != 0))
   //                                  ;

   sirv_gnrl_dfflr #(ROWBUF_IDX_W)   rowbuf_cnt_dfflr (rowbuf_cnt_ena, rowbuf_cnt_nxt, rowbuf_cnt_r, nice_clk, nice_rst_n);

   // recieve data buffer, to make sure rowsum ops come from registers 
   wire rcv_data_buf_ena;
   wire rcv_data_buf_set;
   wire rcv_data_buf_clr;
   wire rcv_data_buf_valid;
   wire [`E203_XLEN-1:0] rcv_data_buf; 
   wire [ROWBUF_IDX_W-1:0] rcv_data_buf_idx; 
   wire [ROWBUF_IDX_W-1:0] rcv_data_buf_idx_nxt; 

   assign rcv_data_buf_set = rowbuf_icb_rsp_hsked;
   assign rcv_data_buf_clr = rowbuf_rsp_hsked;
   assign rcv_data_buf_ena = rcv_data_buf_clr | rcv_data_buf_set;
   assign rcv_data_buf_idx_nxt =   ({ROWBUF_IDX_W{rcv_data_buf_clr}} & {ROWBUF_IDX_W{1'b0}})
                                 | ({ROWBUF_IDX_W{rcv_data_buf_set}} & rowbuf_cnt_r        );

   sirv_gnrl_dfflr #(1)   rcv_data_buf_valid_dfflr (1'b1, rcv_data_buf_ena, rcv_data_buf_valid, nice_clk, nice_rst_n);
   sirv_gnrl_dfflr #(`E203_XLEN)   rcv_data_buf_dfflr (rcv_data_buf_ena, nice_icb_rsp_rdata, rcv_data_buf, nice_clk, nice_rst_n);
   sirv_gnrl_dfflr #(ROWBUF_IDX_W)   rowbuf_cnt_d_dfflr (rcv_data_buf_ena, rcv_data_buf_idx_nxt, rcv_data_buf_idx, nice_clk, nice_rst_n);

   // rowsum accumulator 
   wire [`E203_XLEN-1:0] rowsum_acc_r;
   wire [`E203_XLEN-1:0] rowsum_acc_nxt;
   wire [`E203_XLEN-1:0] rowsum_acc_adder;
   wire rowsum_acc_ena;
   wire rowsum_acc_set;
   wire rowsum_acc_flg;
   wire nice_icb_cmd_valid_rowsum;
   wire [`E203_XLEN-1:0] rowsum_res;

   assign rowsum_acc_set = rcv_data_buf_valid & (rcv_data_buf_idx == {ROWBUF_IDX_W{1'b0}});
   assign rowsum_acc_flg = rcv_data_buf_valid & (rcv_data_buf_idx != {ROWBUF_IDX_W{1'b0}});
   assign rowsum_acc_adder = rcv_data_buf + rowsum_acc_r;
   assign rowsum_acc_ena = rowsum_acc_set | rowsum_acc_flg;
   assign rowsum_acc_nxt =   ({`E203_XLEN{rowsum_acc_set}} & rcv_data_buf)
                           | ({`E203_XLEN{rowsum_acc_flg}} & rowsum_acc_adder)
                           ;
 
   sirv_gnrl_dfflr #(`E203_XLEN)   rowsum_acc_dfflr (rowsum_acc_ena, rowsum_acc_nxt, rowsum_acc_r, nice_clk, nice_rst_n);

   assign rowsum_done = state_is_rowsum & nice_rsp_hsked;
   assign rowsum_res  = rowsum_acc_r;

   // rowsum finishes when the last acc data is added to rowsum_acc_r  
   assign nice_rsp_valid_rowsum = state_is_rowsum & (rcv_data_buf_idx == clonum) & ~rowsum_acc_flg;

   // nice_icb_cmd_valid sets when rcv_data_buf_idx is not full in LBUF
   assign nice_icb_cmd_valid_rowsum = state_is_rowsum & (rcv_data_buf_idx < clonum) & ~rowsum_acc_flg;

   //////////// rowbuf
   // rowbuf access list:
   //  1. lbuf will write to rowbuf, write data comes from memory, data length is defined by clonum 
   //  2. sbuf will read from rowbuf, and store it to memory, data length is defined by clonum 
   //  3. rowsum will accumulate data, and store to rowbuf, data length is defined by clonum 
   wire [`E203_XLEN-1:0] rowbuf_r [ROWBUF_DP-1:0];
   wire [`E203_XLEN-1:0] rowbuf_wdat [ROWBUF_DP-1:0];
   wire [ROWBUF_DP-1:0]  rowbuf_we;
   wire [ROWBUF_IDX_W-1:0] rowbuf_idx_mux; 
   wire [`E203_XLEN-1:0] rowbuf_wdat_mux; 
   wire rowbuf_wr_mux; 
   //wire [ROWBUF_IDX_W-1:0] sbuf_idx; 
   
   // lbuf write to rowbuf
   wire [ROWBUF_IDX_W-1:0] lbuf_idx = lbuf_cnt; 
   wire lbuf_wr = state_is_lbuf & nice_icb_rsp_hsked;
   wire [`E203_XLEN-1:0] lbuf_wdata = nice_icb_rsp_rdata;

   // rowsum write to rowbuf(column accumulated data)
   wire [ROWBUF_IDX_W-1:0] rowsum_idx = rcv_data_buf_idx; 
   wire rowsum_wr = rcv_data_buf_valid; 
   wire [`E203_XLEN-1:0] rowsum_wdata = rowbuf_r[rowsum_idx] + rcv_data_buf;

   // rowbuf write mux
   assign rowbuf_wdat_mux =   ({`E203_XLEN{lbuf_wr  }} & lbuf_wdata  )
                            | ({`E203_XLEN{rowsum_wr}} & rowsum_wdata)
                            ;
   assign rowbuf_wr_mux   =  lbuf_wr | rowsum_wr;
   assign rowbuf_idx_mux  =   ({ROWBUF_IDX_W{lbuf_wr  }} & lbuf_idx  )
                            | ({ROWBUF_IDX_W{rowsum_wr}} & rowsum_idx)
                            ;  

   // rowbuf inst
   genvar i;
   generate 
     for (i=0; i<ROWBUF_DP; i=i+1) begin:gen_rowbuf
       assign rowbuf_we[i] =   (rowbuf_wr_mux & (rowbuf_idx_mux == i[ROWBUF_IDX_W-1:0]))
                             ;
  
       assign rowbuf_wdat[i] =   ({`E203_XLEN{rowbuf_we[i]}} & rowbuf_wdat_mux   )
                               ;
  
       sirv_gnrl_dfflr #(`E203_XLEN) rowbuf_dfflr (rowbuf_we[i], rowbuf_wdat[i], rowbuf_r[i], nice_clk, nice_rst_n);
     end
   endgenerate

   //////////// mem aacess addr management
   wire [`E203_XLEN-1:0] maddr_acc_r; 
   assign nice_icb_cmd_hsked = nice_icb_cmd_valid & nice_icb_cmd_ready; 
   // custom3_lbuf 
   //wire [`E203_XLEN-1:0] lbuf_maddr    = state_is_idle ? nice_req_rs1 : maddr_acc_r ; 
   wire lbuf_maddr_ena    =   (state_is_idle & custom3_lbuf & nice_icb_cmd_hsked)
                            | (state_is_lbuf & nice_icb_cmd_hsked)
                            ;

   // custom3_sbuf 
   //wire [`E203_XLEN-1:0] sbuf_maddr    = state_is_idle ? nice_req_rs1 : maddr_acc_r ; 
   wire sbuf_maddr_ena    =   (state_is_idle & custom3_sbuf & nice_icb_cmd_hsked)
                            | (state_is_sbuf & nice_icb_cmd_hsked)
                            ;

   // custom3_rowsum
   //wire [`E203_XLEN-1:0] rowsum_maddr  = state_is_idle ? nice_req_rs1 : maddr_acc_r ; 
   wire rowsum_maddr_ena  =   (state_is_idle & custom3_rowsum & nice_icb_cmd_hsked)
                            | (state_is_rowsum & nice_icb_cmd_hsked)
                            ;

   // maddr acc 
   //wire  maddr_incr = lbuf_maddr_ena | sbuf_maddr_ena | rowsum_maddr_ena | rbuf_maddr_ena;
   wire  maddr_ena = lbuf_maddr_ena | sbuf_maddr_ena | rowsum_maddr_ena;
   wire  maddr_ena_idle = maddr_ena & state_is_idle;

   wire [`E203_XLEN-1:0] maddr_acc_op1 = maddr_ena_idle ? nice_req_rs1 : maddr_acc_r; // not reused
   wire [`E203_XLEN-1:0] maddr_acc_op2 = maddr_ena_idle ? `E203_XLEN'h4 : `E203_XLEN'h4; 

   wire [`E203_XLEN-1:0] maddr_acc_next = maddr_acc_op1 + maddr_acc_op2;
   wire  maddr_acc_ena = maddr_ena;

   sirv_gnrl_dfflr #(`E203_XLEN)   maddr_acc_dfflr (maddr_acc_ena, maddr_acc_next, maddr_acc_r, nice_clk, nice_rst_n);

   ////////////////////////////////////////////////////////////
   // Control cmd_req
   ////////////////////////////////////////////////////////////
   assign nice_req_hsked = nice_req_valid & nice_req_ready;
   assign nice_req_ready = state_is_idle & (custom_mem_op ? nice_icb_cmd_ready : 1'b1);

   ////////////////////////////////////////////////////////////
   // Control cmd_rsp
   ////////////////////////////////////////////////////////////
   assign nice_rsp_hsked = nice_rsp_valid & nice_rsp_ready; 
   assign nice_icb_rsp_hsked = nice_icb_rsp_valid & nice_icb_rsp_ready;
   assign nice_rsp_valid = nice_rsp_valid_rowsum | nice_rsp_valid_sbuf | nice_rsp_valid_lbuf;
   assign nice_rsp_rdat  = {`E203_XLEN{state_is_rowsum}} & rowsum_res;

   // memory access bus error
   //assign nice_rsp_err_irq  =   (nice_icb_rsp_hsked & nice_icb_rsp_err)
   //                          | (nice_req_hsked & illgel_instr)
   //                          ; 
   assign nice_rsp_err   =   (nice_icb_rsp_hsked & nice_icb_rsp_err);

   ////////////////////////////////////////////////////////////
   // Memory lsu
   ////////////////////////////////////////////////////////////
   // memory access list:
   //  1. In IDLE, custom_mem_op will access memory(lbuf/sbuf/rowsum)
   //  2. In LBUF, it will read from memory as long as lbuf_cnt_r is not full
   //  3. In SBUF, it will write to memory as long as sbuf_cnt_r is not full
   //  3. In ROWSUM, it will read from memory as long as rowsum_cnt_r is not full
   //assign nice_icb_rsp_ready = state_is_ldst_rsp & nice_rsp_ready; 
   // rsp always ready
   assign nice_icb_rsp_ready = 1'b1; 
   wire [ROWBUF_IDX_W-1:0] sbuf_idx = sbuf_cmd_cnt; 

   assign nice_icb_cmd_valid =   (state_is_idle & nice_req_valid & custom_mem_op)
                              | nice_icb_cmd_valid_lbuf
                              | nice_icb_cmd_valid_sbuf
                              | nice_icb_cmd_valid_rowsum
                              ;
   assign nice_icb_cmd_addr  = (state_is_idle & custom_mem_op) ? nice_req_rs1 :
                              maddr_acc_r;
   assign nice_icb_cmd_read  = (state_is_idle & custom_mem_op) ? (custom3_lbuf | custom3_rowsum) : 
                              state_is_sbuf ? 1'b0 : 
                              1'b1;
   assign nice_icb_cmd_wdata = (state_is_idle & custom3_sbuf) ? rowbuf_r[sbuf_idx] :
                              state_is_sbuf ? rowbuf_r[sbuf_idx] : 
                              `E203_XLEN'b0; 

   //assign nice_icb_cmd_wmask = {`sirv_XLEN_MW{custom3_sbuf}} & 4'b1111;
   assign nice_icb_cmd_size  = 2'b10;
   assign nice_mem_holdup    =  state_is_lbuf | state_is_sbuf | state_is_rowsum; 

   ////////////////////////////////////////////////////////////
   // nice_active
   ////////////////////////////////////////////////////////////
   assign nice_active = state_is_idle ? nice_req_valid : 1'b1;

endmodule
`endif//}


