//=====================================================================
//
// Designer   : FyF
//
// Description:
//  The Module to realize a 10 * 5 Systolic Array
//  Mul width: int9   Add width: int32
//
// ====================================================================


module systolic_array_10_5 #(
    parameter int L_WIDTH    = 32,
    parameter int S_WIDTH    = 8,
    parameter int ROWS       = 10,
    parameter int COLS       = 5
)(
    // Clock and reset
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic        [ROWS-1:0]       en_left,
    input  logic signed [8:0]            data_left [ROWS], // int9

    input  logic        [COLS-1:0]       en_up,
    input  logic signed [31:0]           data_up   [COLS], // int32

    output logic        [COLS-1:0]       en_down,
    output logic signed [31:0]           data_down [COLS], // int32

    input  logic                         mode      [ROWS][COLS]
);

    // --------------------------------------------------------------------------------
    // en_vert[i][j] and data_vert[i][j] represent signals from row (i-1) to row i 
    //   at column j (vertical direction).
    // en_horz[i][j] and data_horz[i][j] represent signals from column (j-1) to column j 
    //   at row i (horizontal direction).
    // Using dimensions up to ROWS + 1 and COLS + 1 for boundary connections.
    // --------------------------------------------------------------------------------

    // Vertical connections: dimension is [0..ROWS] in row direction, [0..COLS-1] in column
    logic        [0:ROWS][COLS-1:0]                 en_vert;
    logic signed [0:ROWS][COLS-1:0][L_WIDTH-1:0]    data_vert; // int32

    // Horizontal connections: dimension is [0..ROWS-1] in row, [0..COLS] in column
    logic        [ROWS-1:0][0:COLS]                 en_horz;
    logic signed [ROWS-1:0][0:COLS][8:0]            data_horz; // int9

    // --------------------------------------------------------------------------------
    // Connect the left boundary with en_left/data_left.
    // --------------------------------------------------------------------------------
    for (genvar i = 0; i < ROWS; i++) begin
        assign en_horz[i][0]   = en_left[i];
        assign data_horz[i][0] = data_left[i];
    end

    // --------------------------------------------------------------------------------
    // Connect the upper boundary with en_up/data_up.
    // --------------------------------------------------------------------------------
    for (genvar j = 0; j < COLS; j++) begin
        assign en_vert[0][j]   = en_up[j];
        assign data_vert[0][j] = data_up[j];
    end

    // --------------------------------------------------------------------------------
    // Connect the bottom boundary
    // --------------------------------------------------------------------------------
    for (genvar j = 0; j < COLS; j++) begin : DOWN_CONNECT
        assign en_down[j]    = en_vert[ROWS][j];
        assign data_down[j]  = data_vert[ROWS][j];
    end

    // --------------------------------------------------------------------------------
    // Generate the systolic array of ROWS×COLS Processing Elements (PE).
    // For the last column (j=COLS-1), instantiate PE_r, which has no right output.
    // --------------------------------------------------------------------------------
    for (genvar i = 0; i < ROWS; i++) begin : ROW_GEN
        for (genvar j = 0; j < COLS; j++) begin : COL_GEN
            if (j < COLS-1) begin
                PE #(
                    .L_WIDTH(L_WIDTH),
                    .S_WIDTH(S_WIDTH)
                ) pe_inst (
                    .PE_clk       (clk),
                    .PE_rst_n     (rst_n),
                    .PE_mode      (mode[i][j]),

                    .PE_en_up     (en_vert  [i][j]),
                    .PE_data_up   (data_vert[i][j]),
                    .PE_en_left   (en_horz  [i][j]),
                    .PE_data_left (data_horz[i][j]),

                    .PE_en_right  (en_horz  [i][j+1]),
                    .PE_data_right(data_horz[i][j+1]),
                    .PE_en_down   (en_vert  [i+1][j]),
                    .PE_data_down (data_vert[i+1][j])
                );
            end
            else begin
                PE_r #(
                    .L_WIDTH(L_WIDTH),
                    .S_WIDTH(S_WIDTH)
                ) pe_r_inst (
                    .PE_clk       (clk),
                    .PE_rst_n     (rst_n),
                    .PE_mode      (mode[i][j]),

                    .PE_en_up     (en_vert  [i][j]),
                    .PE_data_up   (data_vert[i][j]),
                    .PE_en_left   (en_horz  [i][j]),
                    .PE_data_left (data_horz[i][j]),

                    .PE_en_down   (en_vert  [i+1][j]),
                    .PE_data_down (data_vert[i+1][j])
                );
            end
        end
    end


endmodule

