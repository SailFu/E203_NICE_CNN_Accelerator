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
  

  ////////////////////////////////////////////////////////////
  // store Matrix A 4*4
  localparam signed [DATA_WIDTH-1:0] store_0_0 = 1;
  localparam signed [DATA_WIDTH-1:0] store_0_1 = 2;
  localparam signed [DATA_WIDTH-1:0] store_0_2 = 3;
  localparam signed [DATA_WIDTH-1:0] store_0_3 = 4;
  localparam signed [DATA_WIDTH-1:0] store_1_0 = 5;
  localparam signed [DATA_WIDTH-1:0] store_1_1 = 6;
  localparam signed [DATA_WIDTH-1:0] store_1_2 = 7;
  localparam signed [DATA_WIDTH-1:0] store_1_3 = 8;
  localparam signed [DATA_WIDTH-1:0] store_2_0 = 9;
  localparam signed [DATA_WIDTH-1:0] store_2_1 = 10;
  localparam signed [DATA_WIDTH-1:0] store_2_2 = 11;
  localparam signed [DATA_WIDTH-1:0] store_2_3 = 12;
  localparam signed [DATA_WIDTH-1:0] store_3_0 = 13;
  localparam signed [DATA_WIDTH-1:0] store_3_1 = 14;
  localparam signed [DATA_WIDTH-1:0] store_3_2 = 15;
  localparam signed [DATA_WIDTH-1:0] store_3_3 = 16;

  // Matrix B 4*3
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
    .array_data_down_3_3   (array_data_down_3_3)
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
    $display("*********************************");
    $display("*********START SIMULATION********");
    $display("*********************************");
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
    array_en_up_0_0   = 0;
    array_en_up_0_1   = 0;
    array_en_up_0_2   = 0;
    array_en_up_0_3   = 0;

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

    @(negedge array_clk);
    array_data_left_0_0 = 0;
    array_data_left_1_0 = 0;
    array_data_left_2_0 = 0;
    array_data_left_3_0 = matrix_3_2;

    print_data();

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

    @(negedge array_clk); print_data();
    @(negedge array_clk); print_data();
    @(negedge array_clk); print_data();
    @(negedge array_clk); print_data();
    @(negedge array_clk); print_data();

    #1000;

    $display("*********************************");
    $display("**********END SIMULATION*********");
    $display("*********************************");

    $finish;
  end


  initial begin
    $fsdbDumpfile("tb_systolic_array_4_4.fsdb");
    $fsdbDumpvars(0, tb_systolic_array_4_4, "+mda");
  end


endmodule
