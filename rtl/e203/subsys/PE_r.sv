//=====================================================================
//
// Designer   : FyF
//
// Description:
//  The Module to realize a far right PE in Systolic Array
//
// ====================================================================

module PE_r  #(
  parameter int L_WIDTH = 32,
  parameter int S_WIDTH = 8
)(
  // system
  input  logic                     PE_clk,
  input  logic                     PE_rst_n,
          
  // control                 
  input  logic                     PE_mode,      // fix weight
  input  logic                     PE_en_up,     // store mode
  input  logic                     PE_en_left,   // calculation mode
  output logic                     PE_en_down,

  // data  
  input  logic signed [31:0]       PE_data_up,
  output logic signed [31:0]       PE_data_down,

  input  logic signed [8:0]        PE_data_left
);

  typedef logic signed [31:0] int32_t;
  typedef logic signed [8:0]  int9_t;

  logic       en_down_reg;
  int32_t     data_down_reg;
  int9_t      weight_reg;

  always_ff @(posedge PE_clk or negedge PE_rst_n) begin
    if (!PE_rst_n) begin
      en_down_reg    <= 1'b0;
      data_down_reg  <= '0;
      weight_reg     <= '0;
    end
    else begin
      // ----------------------
      // store mode
      // ----------------------
      if (PE_en_up & PE_mode) begin
        weight_reg    <= PE_data_up[9-1:0]; 
        data_down_reg <= PE_data_up;
        en_down_reg   <= 1'b1;
      end 
      else begin
        en_down_reg   <= 1'b0;
      end

      // ----------------------
      // calculation mode
      // ----------------------
      if (PE_en_left) begin
        data_down_reg  <= PE_data_left * weight_reg + PE_data_up;
      end 
    end
  end

  // output
  assign PE_en_down    = en_down_reg;
  assign PE_data_down  = data_down_reg;

endmodule


