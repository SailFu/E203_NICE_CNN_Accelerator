//=====================================================================
//
// Designer   : FyF
//
// Description:
//  The Module to realize a PE
//
// ====================================================================

module PE  #(
    parameter DATA_WIDTH = 32
  )(
    // system
    input  wire        PE_clk,
    input  wire        PE_rst_n,

    // control
    input  wire        PE_up_en,     // store mode
    input  wire        PE_left_en,   // calculation mode
    output wire        PE_right_en,
    output wire        PE_down_en,

    // data
    input  wire [DATA_WIDTH-1:0]      PE_data_up,
    input  wire [DATA_WIDTH-1:0]      PE_data_left,
    output wire [DATA_WIDTH-1:0]      PE_data_right,
    output wire [DATA_WIDTH-1:0]      PE_data_down
  );


  reg en_right_reg;
  reg en_down_reg;
  reg [DATA_WIDTH-1:0] data_right_reg;
  reg [DATA_WIDTH-1:0] data_down_reg;

  reg [DATA_WIDTH-1:0] weight_reg;
  reg [DATA_WIDTH-1:0] sum_reg;
  
  always @(posedge PE_clk or negedge PE_rst_n)
  begin
    if(!PE_rst_n) begin
      data_right_reg <= 0;
      data_down_reg <= 0;
      weight_reg <= 0;
      sum_reg <= 0;
      en_down_reg <= 1'b0;
      en_right_reg <= 1'b0;
    end

    else begin
      if(PE_up_en) begin     // store mode
        weight_reg <= PE_data_up;
        data_down_reg <= weight_reg;
        en_down_reg <= 1'b1;
      end else begin
        en_down_reg <= 1'b0;
      end

      if(PE_left_en) begin   // calculation mode
        data_right_reg <= PE_data_left;
        data_down_reg <= (PE_data_left * weight_reg) + sum_reg;
        sum_reg <= PE_data_up;
        en_right_reg <= 1'b1;
      end else begin
        en_right_reg <= 1'b0;
      end
    end
  end


  assign PE_right_en = en_right_reg;
  assign PE_down_en = en_down_reg;
  assign PE_data_right = data_right_reg;
  assign PE_data_down = data_down_reg;

endmodule
