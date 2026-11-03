`timescale 1ns/1ps
module uart_tx #(parameter CLK_HZ=50000000,BAUD=9600)(
 input wire clk,rst,start,input wire [7:0] data,output wire tx,output reg busy);
 localparam DIV=CLK_HZ/BAUD;
 reg [9:0] bits;reg [3:0] index;reg [15:0] count;
 assign tx=busy?bits[0]:1'b1;
 always @(posedge clk) if(rst) begin busy<=0;bits<=1023;index<=0;count<=0;end
 else if(!busy) begin
  if(start) begin bits<={1'b1,data,1'b0};busy<=1;index<=0;count<=DIV-1;end
 end else if(count!=0) count<=count-1'b1;
 else if(index==9) busy<=0;
 else begin bits<={1'b1,bits[9:1]};index<=index+1'b1;count<=DIV-1;end
endmodule
