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
    input  wire        PE_mode,      // fix weight
    input  wire        PE_en_up,     // store mode
    input  wire        PE_en_left,   // calculation mode
    output wire        PE_en_right,
    output wire        PE_en_down,

    // data
    input  wire signed [DATA_WIDTH-1:0]      PE_data_up,
    input  wire signed [DATA_WIDTH-1:0]      PE_data_left,
    output wire signed [DATA_WIDTH-1:0]      PE_data_right,
    output wire signed [DATA_WIDTH-1:0]      PE_data_down
  );


  reg en_right_reg;
  reg en_down_reg;
  reg signed [DATA_WIDTH-1:0] data_right_reg;
  reg signed [DATA_WIDTH-1:0] data_down_reg;

  reg signed [DATA_WIDTH-1:0] weight_reg;
  
  always @(posedge PE_clk or negedge PE_rst_n)
  begin
    if(!PE_rst_n) begin
      en_down_reg <= 1'b0;
      en_right_reg <= 1'b0;
      data_right_reg <= {DATA_WIDTH{1'b0}};
      data_down_reg <= {DATA_WIDTH{1'b0}};
      weight_reg <= {DATA_WIDTH{1'b0}};
    end

    else begin
      if(PE_en_up & PE_mode) begin             // store mode
        weight_reg <= PE_data_up;
        data_down_reg <= PE_data_up;
        en_down_reg <= 1'b1;
      end else begin
        en_down_reg <= 1'b0;
      end

      if(PE_en_left) begin                     // calculation mode
        data_right_reg <= PE_data_left;
        data_down_reg <= (PE_data_left * weight_reg) + PE_data_up;
        en_right_reg <= 1'b1;
      end else begin
        en_right_reg <= 1'b0;
      end
    end
  end

  // module output signals
  assign PE_en_right = en_right_reg;
  assign PE_en_down = en_down_reg;
  assign PE_data_right = data_right_reg;
  assign PE_data_down = data_down_reg;

endmodule
