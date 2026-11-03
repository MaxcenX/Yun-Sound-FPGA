`timescale 1ns/1ps
// Command accepted -> complete left AND right I2S words, ideal codec clock model.
// Does NOT simulate analog DAC/filter or sensor latency.
module tb_latency;
 reg clk=0,rst=1,b=1,lr=1;
 always #10 clk=~clk;
 always #162.760417 b=~b;
 integer slot=63;
 always @(negedge b) begin
  slot=(slot+1)%64;
  if(slot==0) lr=0;
  if(slot==32) lr=1;
 end
 reg valid=0;reg [1:0] op=0;
 wire tick,ok,sd,ready,sv,overrun;wire [31:0] active;wire signed [15:0] pcm;
 synth32_engine synth(clk,rst,tick,valid,op,5'd0,32'd39370534,2'd2,8'd255,
  16'd2048,16'd256,16'd49152,16'd65535,ready,pcm,sv,active,overrun);
 i2s_codec_master tx(clk,rst,b,lr,pcm,sd,tick,ok);
 integer k,n;
 reg [15:0] left,right;
 realtime accepted,elapsed,max_latency=0;
 task command;
 input [1:0] operation;
 begin
  @(negedge clk);valid=1;op=operation;
  @(posedge clk);while(!ready)@(posedge clk);accepted=$realtime;
  @(negedge clk);valid=0;
 end endtask
 task capture;
 begin
  @(negedge lr);@(posedge b);left=0;
  for(k=0;k<16;k=k+1) begin @(posedge b);left={left[14:0],sd};end
  @(posedge lr);@(posedge b);right=0;
  for(k=0;k<16;k=k+1) begin @(posedge b);right={right[14:0],sd};end
  if(left!==right) $fatal(1,"latency test stereo mismatch");
 end endtask
 initial begin
  repeat(4) @(negedge clk);rst=0;wait(ok);
  for(n=0;n<16;n=n+1) begin
   command(1);repeat(5) capture;
   if(pcm!==0) $fatal(1,"latency baseline not silent");
   @(negedge lr);#(n*1250+5);
   command(0);
   capture;
   while(left==0) capture;
   elapsed=$realtime-accepted;
   if(elapsed>max_latency) max_latency=elapsed;
   if(elapsed>100000.0 || overrun) $fatal(1,"digital latency >100us: %f",elapsed);
   $display("LATENCY trial=%0d both_words_us=%0.3f",n,elapsed/1000.0);
  end
  $display("PASS: 16 command phases, first nonzero stereo I2S pair max %0.3f us (digital only)",max_latency/1000.0);
  $finish;
 end
 initial begin #10000000;$fatal(1,"latency timeout");end
endmodule
