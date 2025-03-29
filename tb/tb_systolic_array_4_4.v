`timescale 1ns/1ps

module tb_systolic_array_4_4;

  parameter DATA_WIDTH = 32;
  
  reg                          array_clk;
  reg                          array_rst_n;
  
  // left
  reg                          array_en_left_0_0, array_en_left_1_0, array_en_left_2_0, array_en_left_3_0;
  reg signed  [DATA_WIDTH-1:0] array_data_left_0_0, array_data_left_1_0, array_data_left_2_0, array_data_left_3_0;
  
  // up
  reg                          array_en_up_0_0, array_en_up_0_1, array_en_up_0_2, array_en_up_0_3;
  reg signed  [DATA_WIDTH-1:0] array_data_up_0_0, array_data_up_0_1, array_data_up_0_2, array_data_up_0_3;
  
  // down
  wire                         array_en_down_3_0, array_en_down_3_1, array_en_down_3_2, array_en_down_3_3;
  wire signed [DATA_WIDTH-1:0] array_data_down_3_0, array_data_down_3_1, array_data_down_3_2, array_data_down_3_3;
  
  reg                          array_mode_0_0, array_mode_0_1, array_mode_0_2, array_mode_0_3;
  reg                          array_mode_1_0, array_mode_1_1, array_mode_1_2, array_mode_1_3;
  reg                          array_mode_2_0, array_mode_2_1, array_mode_2_2, array_mode_2_3;
  reg                          array_mode_3_0, array_mode_3_1, array_mode_3_2, array_mode_3_3;
  

  ////////////////////////////////////////////////////////////
  // compute A * B
  // store Matrix A 4*4
  // | 1  2  3  4  |
  // | 5  6  7  8  |
  // | 9  10 11 12 |
  // | 13 14 15 16 |
  // The storage matrix A needs to be transposed => A'
  localparam signed [DATA_WIDTH-1:0] store_0_0 = 1;
  localparam signed [DATA_WIDTH-1:0] store_0_1 = 5;
  localparam signed [DATA_WIDTH-1:0] store_0_2 = 9;
  localparam signed [DATA_WIDTH-1:0] store_0_3 = 13;
  localparam signed [DATA_WIDTH-1:0] store_1_0 = 2;
  localparam signed [DATA_WIDTH-1:0] store_1_1 = 6;
  localparam signed [DATA_WIDTH-1:0] store_1_2 = 10;
  localparam signed [DATA_WIDTH-1:0] store_1_3 = 14;
  localparam signed [DATA_WIDTH-1:0] store_2_0 = 3;
  localparam signed [DATA_WIDTH-1:0] store_2_1 = 7;
  localparam signed [DATA_WIDTH-1:0] store_2_2 = 11;
  localparam signed [DATA_WIDTH-1:0] store_2_3 = 15;
  localparam signed [DATA_WIDTH-1:0] store_3_0 = 4;
  localparam signed [DATA_WIDTH-1:0] store_3_1 = 8;
  localparam signed [DATA_WIDTH-1:0] store_3_2 = 12;
  localparam signed [DATA_WIDTH-1:0] store_3_3 = 16;

  // Matrix B 4*3
  // | 1  2  3  |
  // | 4  5  6  |
  // | 7  8  9  |
  // | 10 11 12 |
  localparam signed [DATA_WIDTH-1:0] matrix_0_0 = 1;
  localparam signed [DATA_WIDTH-1:0] matrix_0_1 = 2;
  localparam signed [DATA_WIDTH-1:0] matrix_0_2 = 3;
  localparam signed [DATA_WIDTH-1:0] matrix_1_0 = 4;
  localparam signed [DATA_WIDTH-1:0] matrix_1_1 = 5;
  localparam signed [DATA_WIDTH-1:0] matrix_1_2 = 6;
  localparam signed [DATA_WIDTH-1:0] matrix_2_0 = 7;
  localparam signed [DATA_WIDTH-1:0] matrix_2_1 = 8;
  localparam signed [DATA_WIDTH-1:0] matrix_2_2 = 9;
  localparam signed [DATA_WIDTH-1:0] matrix_3_0 = 10;
  localparam signed [DATA_WIDTH-1:0] matrix_3_1 = 11;
  localparam signed [DATA_WIDTH-1:0] matrix_3_2 = 12;

  // the A * B output should be
  // | 70  80  90  |
  // | 158 184 210 |
  // | 246 288 330 |
  // | 334 392 450 |
  reg signed        [DATA_WIDTH-1:0] output_matrix_0_0, output_matrix_0_1, output_matrix_0_2;
  reg signed        [DATA_WIDTH-1:0] output_matrix_1_0, output_matrix_1_1, output_matrix_1_2;
  reg signed        [DATA_WIDTH-1:0] output_matrix_2_0, output_matrix_2_1, output_matrix_2_2;
  reg signed        [DATA_WIDTH-1:0] output_matrix_3_0, output_matrix_3_1, output_matrix_3_2;
  /////////////////////////////////////////////////////////////


  systolic_array_4_4 #(.DATA_WIDTH(DATA_WIDTH))
  DUT (
    .array_clk             (array_clk),
    .array_rst_n           (array_rst_n),
    
    // left
    .array_en_left_0_0     (array_en_left_0_0),
    .array_en_left_1_0     (array_en_left_1_0),
    .array_en_left_2_0     (array_en_left_2_0),
    .array_en_left_3_0     (array_en_left_3_0),
    .array_data_left_0_0   (array_data_left_0_0),
    .array_data_left_1_0   (array_data_left_1_0),
    .array_data_left_2_0   (array_data_left_2_0),
    .array_data_left_3_0   (array_data_left_3_0),
    
    // up
    .array_en_up_0_0       (array_en_up_0_0),
    .array_en_up_0_1       (array_en_up_0_1),
    .array_en_up_0_2       (array_en_up_0_2),
    .array_en_up_0_3       (array_en_up_0_3),
    .array_data_up_0_0     (array_data_up_0_0),
    .array_data_up_0_1     (array_data_up_0_1),
    .array_data_up_0_2     (array_data_up_0_2),
    .array_data_up_0_3     (array_data_up_0_3),
    
    // down
    .array_en_down_3_0     (array_en_down_3_0),
    .array_en_down_3_1     (array_en_down_3_1),
    .array_en_down_3_2     (array_en_down_3_2),
    .array_en_down_3_3     (array_en_down_3_3),
    .array_data_down_3_0   (array_data_down_3_0),
    .array_data_down_3_1   (array_data_down_3_1),
    .array_data_down_3_2   (array_data_down_3_2),
    .array_data_down_3_3   (array_data_down_3_3),

    // mode
    .array_mode_0_0        (array_mode_0_0),
    .array_mode_0_1        (array_mode_0_1),
    .array_mode_0_2        (array_mode_0_2),
    .array_mode_0_3        (array_mode_0_3),
    .array_mode_1_0        (array_mode_1_0),
    .array_mode_1_1        (array_mode_1_1),
    .array_mode_1_2        (array_mode_1_2),
    .array_mode_1_3        (array_mode_1_3),
    .array_mode_2_0        (array_mode_2_0),
    .array_mode_2_1        (array_mode_2_1),
    .array_mode_2_2        (array_mode_2_2),
    .array_mode_2_3        (array_mode_2_3),
    .array_mode_3_0        (array_mode_3_0),
    .array_mode_3_1        (array_mode_3_1),
    .array_mode_3_2        (array_mode_3_2),
    .array_mode_3_3        (array_mode_3_3)
  );
  

  task print_data;
    begin
      $display("time:%t data_0 = %0d, data_1 = %0d, data_2 = %0d, data_3 = %0d", 
        $time, array_data_down_3_0, array_data_down_3_1, array_data_down_3_2, array_data_down_3_3);
    end
  endtask


  // clk 50MHz
  initial begin
    array_clk = 0;
    forever #10 array_clk = ~array_clk;
  end
  
  // rst_n
  initial begin
    array_rst_n = 0;
    #40;
    array_rst_n = 1;
  end
  
  // Stimulus signal generation
  initial begin
    $display("\n\n");
    $display("***************************************************************");
    $display("************************START SIMULATION***********************");
    $display("***************************************************************");
    $display("\n");
    // set 0
    array_en_left_0_0   = 0;
    array_en_left_1_0   = 0;
    array_en_left_2_0   = 0;
    array_en_left_3_0   = 0;
    array_data_left_0_0 = 0;
    array_data_left_1_0 = 0;
    array_data_left_2_0 = 0;
    array_data_left_3_0 = 0;
    
    array_en_up_0_0   = 0;
    array_en_up_0_1   = 0;
    array_en_up_0_2   = 0;
    array_en_up_0_3   = 0;
    array_data_up_0_0 = 0;
    array_data_up_0_1 = 0;
    array_data_up_0_2 = 0;
    array_data_up_0_3 = 0;

    array_mode_0_0 = 0; array_mode_0_1 = 0; array_mode_0_2 = 0; array_mode_0_3 = 0;
    array_mode_1_0 = 0; array_mode_1_1 = 0; array_mode_1_2 = 0; array_mode_1_3 = 0;
    array_mode_2_0 = 0; array_mode_2_1 = 0; array_mode_2_2 = 0; array_mode_2_3 = 0;
    array_mode_3_0 = 0; array_mode_3_1 = 0; array_mode_3_2 = 0; array_mode_3_3 = 0;
    
    // Wait reset complete
    #40;
    
    // start store wheight
    array_en_up_0_0   = 1;
    array_en_up_0_1   = 1;
    array_en_up_0_2   = 1;
    array_en_up_0_3   = 1;

    array_data_up_0_0 = store_3_0;
    array_data_up_0_1 = store_3_1;
    array_data_up_0_2 = store_3_2;
    array_data_up_0_3 = store_3_3;

    array_mode_0_0 = 1; array_mode_0_1 = 1; array_mode_0_2 = 1; array_mode_0_3 = 1;
    array_mode_1_0 = 1; array_mode_1_1 = 1; array_mode_1_2 = 1; array_mode_1_3 = 1;
    array_mode_2_0 = 1; array_mode_2_1 = 1; array_mode_2_2 = 1; array_mode_2_3 = 1;
    array_mode_3_0 = 1; array_mode_3_1 = 1; array_mode_3_2 = 1; array_mode_3_3 = 1;

    #20;
    
    @(negedge array_clk);
    array_data_up_0_0 = store_2_0;
    array_data_up_0_1 = store_2_1;
    array_data_up_0_2 = store_2_2;
    array_data_up_0_3 = store_2_3;

    @(negedge array_clk);
    array_data_up_0_0 = store_1_0;
    array_data_up_0_1 = store_1_1;
    array_data_up_0_2 = store_1_2;
    array_data_up_0_3 = store_1_3;

    @(negedge array_clk);
    array_data_up_0_0 = store_0_0;
    array_data_up_0_1 = store_0_1;
    array_data_up_0_2 = store_0_2;
    array_data_up_0_3 = store_0_3;

    // start calculation
    @(negedge array_clk);
    array_mode_0_0 = 0; array_mode_0_1 = 0; array_mode_0_2 = 0; array_mode_0_3 = 0;
    array_mode_1_0 = 0; array_mode_1_1 = 0; array_mode_1_2 = 0; array_mode_1_3 = 0;
    array_mode_2_0 = 0; array_mode_2_1 = 0; array_mode_2_2 = 0; array_mode_2_3 = 0;
    array_mode_3_0 = 0; array_mode_3_1 = 0; array_mode_3_2 = 0; array_mode_3_3 = 0;

    array_en_up_0_0   = 0;
    array_en_up_0_1   = 0;
    array_en_up_0_2   = 0;
    array_en_up_0_3   = 0;

    // important !!!
    array_data_up_0_0 = 0;
    array_data_up_0_1 = 0;
    array_data_up_0_2 = 0;
    array_data_up_0_3 = 0;

    array_en_left_0_0 = 1;
    array_en_left_1_0 = 1;
    array_en_left_2_0 = 1;
    array_en_left_3_0 = 1;

    array_data_left_0_0 = matrix_0_0;
    array_data_left_1_0 = 0;
    array_data_left_2_0 = 0;
    array_data_left_3_0 = 0;

    print_data();

    @(negedge array_clk);
    array_data_left_0_0 = matrix_0_1;
    array_data_left_1_0 = matrix_1_0;
    array_data_left_2_0 = 0;
    array_data_left_3_0 = 0;

    print_data();

    @(negedge array_clk);
    array_data_left_0_0 = matrix_0_2;
    array_data_left_1_0 = matrix_1_1;
    array_data_left_2_0 = matrix_2_0;
    array_data_left_3_0 = 0;

    print_data();

    @(negedge array_clk);
    array_data_left_0_0 = 0;
    array_data_left_1_0 = matrix_1_2;
    array_data_left_2_0 = matrix_2_1;
    array_data_left_3_0 = matrix_3_0;

    print_data();
    
    @(negedge array_clk);
    array_data_left_0_0 = 0;
    array_data_left_1_0 = 0;
    array_data_left_2_0 = matrix_2_2;
    array_data_left_3_0 = matrix_3_1;

    print_data();
    @(posedge array_clk); 
    output_matrix_0_0 = array_data_down_3_0;
    
    @(negedge array_clk);
    array_data_left_0_0 = 0;
    array_data_left_1_0 = 0;
    array_data_left_2_0 = 0;
    array_data_left_3_0 = matrix_3_2;

    print_data();
    @(posedge array_clk); 
    output_matrix_0_1 = array_data_down_3_0;
    output_matrix_1_0 = array_data_down_3_1;
    
    @(negedge array_clk);
    array_en_left_0_0 = 0;
    array_en_left_1_0 = 0;
    array_en_left_2_0 = 0;
    array_en_left_3_0 = 0;

    array_data_left_0_0 = 0;
    array_data_left_1_0 = 0;
    array_data_left_2_0 = 0;
    array_data_left_3_0 = 0;

    print_data();
    @(posedge array_clk); 
    output_matrix_0_2 = array_data_down_3_0;
    output_matrix_1_1 = array_data_down_3_1;
    output_matrix_2_0 = array_data_down_3_2;
    
    @(negedge array_clk); print_data();
    @(posedge array_clk); 
    output_matrix_1_2 = array_data_down_3_1;
    output_matrix_2_1 = array_data_down_3_2;
    output_matrix_3_0 = array_data_down_3_3;
    
    @(negedge array_clk); print_data();
    @(posedge array_clk); 
    output_matrix_2_2 = array_data_down_3_2;
    output_matrix_3_1 = array_data_down_3_3;
    
    @(negedge array_clk); print_data();
    @(posedge array_clk); 
    output_matrix_3_2 = array_data_down_3_3;
    
    $display("\n\nThe Output Matrix is:");
    $display("| %5d %5d %5d |", output_matrix_0_0, output_matrix_0_1, output_matrix_0_2);
    $display("| %5d %5d %5d |", output_matrix_1_0, output_matrix_1_1, output_matrix_1_2);
    $display("| %5d %5d %5d |", output_matrix_2_0, output_matrix_2_1, output_matrix_2_2);
    $display("| %5d %5d %5d |", output_matrix_3_0, output_matrix_3_1, output_matrix_3_2);

    #100;

    $display("\n");
    $display("***************************************************************");
    $display("*************************END SIMULATION************************");
    $display("***************************************************************");
    $display("\n\n");

    $finish;
  end


  initial begin
    $fsdbDumpfile("tb_systolic_array_4_4.fsdb");
    $fsdbDumpvars(0, tb_systolic_array_4_4, "+mda");
  end


endmodule
