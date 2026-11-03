`timescale 1ns/1ps
module tb_led595;
reg clk=0,rst=1;always #10 clk=~clk;
reg [11:0] keys=0;wire sdi,sck,lat;
led595_driver #(.CLK_HZ(100000)) dut(clk,rst,keys,sdi,sck,lat);
reg [15:0] shifted=0;integer latches=0,i,old;reg [15:0] expected;
always @(posedge sck) shifted={shifted[14:0],sdi};
always @(posedge lat) latches=latches+1;
function [15:0] wanted;input integer k;begin
case(k)
0:wanted=16'h0010;1:wanted=16'h0008;2:wanted=16'h0004;3:wanted=16'h0002;
4:wanted=16'h0080;5:wanted=16'h0040;6:wanted=16'h0800;7:wanted=16'h0001;
8:wanted=16'h0200;9:wanted=16'h0100;10:wanted=16'h0400;11:wanted=16'h0020;
endcase end endfunction
initial begin repeat(4)@(negedge clk);rst=0;
for(i=0;i<12;i=i+1) begin
 keys=12'b1<<i;expected=wanted(i);old=latches;
 wait(latches>=old+2);@(negedge clk);
 if(shifted!==expected)$fatal(1,"key %d serial %h expected %h",i,shifted,expected);
end
keys=12'hfff;old=latches;wait(latches>=old+2);@(negedge clk);if(shifted!==16'h0fff)$fatal(1,"all lamps");
keys=0;old=latches;wait(latches>=old+2);@(negedge clk);if(shifted!==0)$fatal(1,"off");
$display("PASS all 12 PCB outputs, U1/U2 cascade, all on and off");$finish;end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
