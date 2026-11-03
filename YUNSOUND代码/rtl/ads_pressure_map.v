`timescale 1ns/1ps
// ADC raw voltage = code/2000 V. Fixed measured endpoints: .90V=1800, 0V=0.
// Negative slope sensor; clamped 12-bit pressure. Two registered arithmetic stages.
module ads_pressure_map(input wire clk,rst,enabled,input wire [13:0] raw,
 output reg [11:0] pressure);
 reg [10:0] distance;
 reg [22:0] product;
 always @(posedge clk) begin
  if(rst || !enabled) begin distance<=0;product<=0;pressure<=0;end
  else begin
   if(raw>=1800) distance<=0;
   else if(raw==0) distance<=1800;
   else distance<=1800-raw;
   // 2330/1024 approximates 4095/1800 to <2 output counts across the range.
   product<=distance*12'd2330;
   if(product>=23'd4193280) pressure<=4095;
   else pressure<=product[21:10];
  end
 end
endmodule
