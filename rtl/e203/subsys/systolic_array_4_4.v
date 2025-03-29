//=====================================================================
//
// Designer   : FyF
//
// Description:
//  The Module to realize a 4 * 4 Systolic Array
//
// ====================================================================

module systolic_array_4_4 #(
    parameter DATA_WIDTH = 32
  )(
    // system
    input  wire                    array_clk,
    input  wire                    array_rst_n,

    // left
		input  wire                    array_en_left_0_0,
		input  wire                    array_en_left_1_0,
		input  wire                    array_en_left_2_0,
		input  wire                    array_en_left_3_0,
		input  wire [DATA_WIDTH-1:0]   array_data_left_0_0,	
		input  wire [DATA_WIDTH-1:0]   array_data_left_1_0,
		input  wire [DATA_WIDTH-1:0]   array_data_left_2_0,
		input  wire [DATA_WIDTH-1:0]   array_data_left_3_0,

		// up
		input  wire                    array_en_up_0_0,
		input  wire                    array_en_up_0_1,
		input  wire                    array_en_up_0_2,
		input  wire                    array_en_up_0_3,
		input  wire [DATA_WIDTH-1:0]   array_data_up_0_0,
		input  wire [DATA_WIDTH-1:0]   array_data_up_0_1,
		input  wire [DATA_WIDTH-1:0]   array_data_up_0_2,
		input  wire [DATA_WIDTH-1:0]   array_data_up_0_3,

		// down
		output wire                    array_en_down_3_0,
		output wire                    array_en_down_3_1,
		output wire                    array_en_down_3_2,
		output wire                    array_en_down_3_3,
		output wire [DATA_WIDTH-1:0]   array_data_down_3_0,
		output wire [DATA_WIDTH-1:0]   array_data_down_3_1,
		output wire [DATA_WIDTH-1:0]   array_data_down_3_2,
		output wire [DATA_WIDTH-1:0]   array_data_down_3_3
  );

	wire array_en_0_0_to_0_1;
	wire array_en_0_1_to_0_2;
	wire array_en_0_2_to_0_3;
	wire array_en_1_0_to_1_1;
	wire array_en_1_1_to_1_2;
	wire array_en_1_2_to_1_3;
	wire array_en_2_0_to_2_1;
	wire array_en_2_1_to_2_2;
	wire array_en_2_2_to_2_3;
	wire array_en_3_0_to_3_1;
	wire array_en_3_1_to_3_2;
	wire array_en_3_2_to_3_3;

	wire array_en_0_0_to_1_0;
	wire array_en_0_1_to_1_1;
	wire array_en_0_2_to_1_2;
	wire array_en_0_3_to_1_3;
	wire array_en_1_0_to_2_0;
	wire array_en_1_1_to_2_1;
	wire array_en_1_2_to_2_2;
	wire array_en_1_3_to_2_3;
	wire array_en_2_0_to_3_0;
	wire array_en_2_1_to_3_1;
	wire array_en_2_2_to_3_2;
	wire array_en_2_3_to_3_3;

	wire [DATA_WIDTH-1:0] array_data_0_0_to_0_1;
	wire [DATA_WIDTH-1:0] array_data_0_1_to_0_2;
	wire [DATA_WIDTH-1:0] array_data_0_2_to_0_3;
	wire [DATA_WIDTH-1:0] array_data_1_0_to_1_1;
	wire [DATA_WIDTH-1:0] array_data_1_1_to_1_2;
	wire [DATA_WIDTH-1:0] array_data_1_2_to_1_3;
	wire [DATA_WIDTH-1:0] array_data_2_0_to_2_1;
	wire [DATA_WIDTH-1:0] array_data_2_1_to_2_2;
	wire [DATA_WIDTH-1:0] array_data_2_2_to_2_3;
	wire [DATA_WIDTH-1:0] array_data_3_0_to_3_1;
	wire [DATA_WIDTH-1:0] array_data_3_1_to_3_2;
	wire [DATA_WIDTH-1:0] array_data_3_2_to_3_3;

	wire [DATA_WIDTH-1:0] array_data_0_0_to_1_0;
	wire [DATA_WIDTH-1:0] array_data_0_1_to_1_1;
	wire [DATA_WIDTH-1:0] array_data_0_2_to_1_2;
	wire [DATA_WIDTH-1:0] array_data_0_3_to_1_3;
	wire [DATA_WIDTH-1:0] array_data_1_0_to_2_0;
	wire [DATA_WIDTH-1:0] array_data_1_1_to_2_1;
	wire [DATA_WIDTH-1:0] array_data_1_2_to_2_2;
	wire [DATA_WIDTH-1:0] array_data_1_3_to_2_3;
	wire [DATA_WIDTH-1:0] array_data_2_0_to_3_0;
	wire [DATA_WIDTH-1:0] array_data_2_1_to_3_1;
	wire [DATA_WIDTH-1:0] array_data_2_2_to_3_2;
	wire [DATA_WIDTH-1:0] array_data_2_3_to_3_3;

	// PE_0_0
	PE #(.DATA_WIDTH(DATA_WIDTH)) PE_0_0 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_up_0_0),
		.PE_en_left        (array_en_left_0_0),
		.PE_en_right       (array_en_0_0_to_0_1),
		.PE_en_down        (array_en_0_0_to_1_0),
		
		.PE_data_up        (array_data_up_0_0),
		.PE_data_left      (array_data_left_0_0),
		.PE_data_right     (array_data_0_0_to_0_1),
		.PE_data_down      (array_data_0_0_to_1_0)
	);

	// PE_0_1
	PE #(.DATA_WIDTH(DATA_WIDTH)) PE_0_1 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_up_0_1),
		.PE_en_left        (array_en_0_0_to_0_1),
		.PE_en_right       (array_en_0_1_to_0_2),
		.PE_en_down        (array_en_0_1_to_1_1),

		.PE_data_up        (array_data_up_0_1),
		.PE_data_left      (array_data_0_0_to_0_1),
		.PE_data_right     (array_data_0_1_to_0_2),
		.PE_data_down      (array_data_0_1_to_1_1)
	);

	// PE_0_2
	PE #(.DATA_WIDTH(DATA_WIDTH)) PE_0_2 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_up_0_2),
		.PE_en_left        (array_en_0_1_to_0_2),
		.PE_en_right       (array_en_0_2_to_0_3),
		.PE_en_down        (array_en_0_2_to_1_2),

		.PE_data_up        (array_data_up_0_2),
		.PE_data_left      (array_data_0_1_to_0_2),
		.PE_data_right     (array_data_0_2_to_0_3),
		.PE_data_down      (array_data_0_2_to_1_2)
	);

	// PE_0_3
	PE_r #(.DATA_WIDTH(DATA_WIDTH)) PE_0_3 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_up_0_3),
		.PE_en_left        (array_en_0_2_to_0_3),
		.PE_en_down        (array_en_0_3_to_1_3),

		.PE_data_up        (array_data_up_0_3),
		.PE_data_left      (array_data_0_2_to_0_3),
		.PE_data_down      (array_data_0_3_to_1_3)
	);

	// PE_1_0
	PE #(.DATA_WIDTH(DATA_WIDTH)) PE_1_0 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_0_0_to_1_0),
		.PE_en_left        (array_en_left_1_0),
		.PE_en_right       (array_en_1_0_to_1_1),
		.PE_en_down        (array_en_1_0_to_2_0),

		.PE_data_up        (array_data_0_0_to_1_0),
		.PE_data_left      (array_data_left_1_0),
		.PE_data_right     (array_data_1_0_to_1_1),
		.PE_data_down      (array_data_1_0_to_2_0)
	);

	// PE_1_1
	PE #(.DATA_WIDTH(DATA_WIDTH)) PE_1_1 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_0_1_to_1_1),
		.PE_en_left        (array_en_1_0_to_1_1),
		.PE_en_right       (array_en_1_1_to_1_2),
		.PE_en_down        (array_en_1_1_to_2_1),

		.PE_data_up        (array_data_0_1_to_1_1),
		.PE_data_left      (array_data_1_0_to_1_1),
		.PE_data_right     (array_data_1_1_to_1_2),
		.PE_data_down      (array_data_1_1_to_2_1)
	);

	// PE_1_2
	PE #(.DATA_WIDTH(DATA_WIDTH)) PE_1_2 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_0_2_to_1_2),
		.PE_en_left        (array_en_1_1_to_1_2),
		.PE_en_right       (array_en_1_2_to_1_3),
		.PE_en_down        (array_en_1_2_to_2_2),

		.PE_data_up        (array_data_0_2_to_1_2),
		.PE_data_left      (array_data_1_1_to_1_2),
		.PE_data_right     (array_data_1_2_to_1_3),
		.PE_data_down      (array_data_1_2_to_2_2)
	);

	// PE_1_3
	PE_r #(.DATA_WIDTH(DATA_WIDTH)) PE_1_3 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_0_3_to_1_3),
		.PE_en_left        (array_en_1_2_to_1_3),
		.PE_en_down        (array_en_1_3_to_2_3),

		.PE_data_up        (array_data_0_3_to_1_3),
		.PE_data_left      (array_data_1_2_to_1_3),
		.PE_data_down      (array_data_1_3_to_2_3)
	);

	// PE_2_0
	PE #(.DATA_WIDTH(DATA_WIDTH)) PE_2_0 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_1_0_to_2_0),
		.PE_en_left        (array_en_left_2_0),
		.PE_en_right       (array_en_2_0_to_2_1),
		.PE_en_down        (array_en_2_0_to_3_0),

		.PE_data_up        (array_data_1_0_to_2_0),
		.PE_data_left      (array_data_left_2_0),
		.PE_data_right     (array_data_2_0_to_2_1),
		.PE_data_down      (array_data_2_0_to_3_0)
	);

	// PE_2_1
	PE #(.DATA_WIDTH(DATA_WIDTH)) PE_2_1 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_1_1_to_2_1),
		.PE_en_left        (array_en_2_0_to_2_1),
		.PE_en_right       (array_en_2_1_to_2_2),
		.PE_en_down        (array_en_2_1_to_3_1),

		.PE_data_up        (array_data_1_1_to_2_1),
		.PE_data_left      (array_data_2_0_to_2_1),
		.PE_data_right     (array_data_2_1_to_2_2),
		.PE_data_down      (array_data_2_1_to_3_1)
	);

	// PE_2_2
	PE #(.DATA_WIDTH(DATA_WIDTH)) PE_2_2 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_1_2_to_2_2),
		.PE_en_left        (array_en_2_1_to_2_2),
		.PE_en_right       (array_en_2_2_to_2_3),
		.PE_en_down        (array_en_2_2_to_3_2),

		.PE_data_up        (array_data_1_2_to_2_2),
		.PE_data_left      (array_data_2_1_to_2_2),
		.PE_data_right     (array_data_2_2_to_2_3),
		.PE_data_down      (array_data_2_2_to_3_2)
	);

	// PE_2_3
	PE_r #(.DATA_WIDTH(DATA_WIDTH)) PE_2_3 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_1_3_to_2_3),
		.PE_en_left        (array_en_2_2_to_2_3),
		.PE_en_down        (array_en_2_3_to_3_3),

		.PE_data_up        (array_data_1_3_to_2_3),
		.PE_data_left      (array_data_2_2_to_2_3),
		.PE_data_down      (array_data_2_3_to_3_3)
	);

	// PE_3_0
	PE #(.DATA_WIDTH(DATA_WIDTH)) PE_3_0 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_2_0_to_3_0),
		.PE_en_left        (array_en_left_3_0),
		.PE_en_right       (array_en_3_0_to_3_1),
		.PE_en_down        (array_en_down_3_0),

		.PE_data_up        (array_data_2_0_to_3_0),
		.PE_data_left      (array_data_left_3_0),
		.PE_data_right     (array_data_3_0_to_3_1),
		.PE_data_down      (array_data_down_3_0)
	);

	// PE_3_1
	PE #(.DATA_WIDTH(DATA_WIDTH)) PE_3_1 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_2_1_to_3_1),
		.PE_en_left        (array_en_3_0_to_3_1),
		.PE_en_right       (array_en_3_1_to_3_2),
		.PE_en_down        (array_en_down_3_1),

		.PE_data_up        (array_data_2_1_to_3_1),
		.PE_data_left      (array_data_3_0_to_3_1),
		.PE_data_right     (array_data_3_1_to_3_2),
		.PE_data_down      (array_data_down_3_1)
	);

	// PE_3_2
	PE #(.DATA_WIDTH(DATA_WIDTH)) PE_3_2 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_2_2_to_3_2),
		.PE_en_left        (array_en_3_1_to_3_2),
		.PE_en_right       (array_en_3_2_to_3_3),
		.PE_en_down        (array_en_down_3_2),

		.PE_data_up        (array_data_2_2_to_3_2),
		.PE_data_left      (array_data_3_1_to_3_2),
		.PE_data_right     (array_data_3_2_to_3_3),
		.PE_data_down      (array_data_down_3_2)
	);

	// PE_3_3
	PE_r #(.DATA_WIDTH(DATA_WIDTH)) PE_3_3 (
		.PE_clk            (array_clk),
		.PE_rst_n          (array_rst_n),

		.PE_en_up          (array_en_2_3_to_3_3),
		.PE_en_left        (array_en_3_2_to_3_3),
		.PE_en_down        (array_en_down_3_3),

		.PE_data_up        (array_data_2_3_to_3_3),
		.PE_data_left      (array_data_3_2_to_3_3),
		.PE_data_down      (array_data_down_3_3)
	);


endmodule


