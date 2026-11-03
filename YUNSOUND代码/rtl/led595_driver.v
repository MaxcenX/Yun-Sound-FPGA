`timescale 1ns/1ps
// Two cascaded 74HC595 chips, 3.3 V, update once per millisecond.
module led595_driver #(parameter CLK_HZ=50000000)(
 input wire clk,rst,input wire [11:0] keys,
 output reg sdi,sck,lat);
 reg [15:0] shift;
 reg [4:0] bits_left;
 reg [1:0] state;
 reg [15:0] pause;
 reg [4:0] step_div;
 always @(posedge clk) begin
  if(rst) begin sdi<=0;sck<=0;lat<=0;shift<=0;bits_left<=0;state<=0;pause<=0;step_div<=0;end
  else if(step_div==24) begin
   step_div<=0;
   case(state)
   0:begin
    sck<=0;lat<=0;
    if(pause>=CLK_HZ/25000-1) begin
     pause<=0;shift<={4'd0,keys[6],keys[10],keys[8],keys[9],keys[4],keys[5],keys[11],keys[0],keys[1],keys[2],keys[3],keys[7]};bits_left<=16;state<=1;
   end else pause<=pause+1'b1;
   end
   1:begin sdi<=shift[15];sck<=0;state<=2;end
   2:begin sck<=1;shift<={shift[14:0],1'b0};state<=3;end
   3:begin sck<=0;
    if(bits_left==1) begin bits_left<=0;lat<=1;state<=0;end
    else begin bits_left<=bits_left-1'b1;state<=1;end
   end
   endcase
  end else step_div<=step_div+1'b1;
 end
endmodule
