`timescale 1ns/1ps
// WM8960 supplies BCLK/LRCLK. Oversample at50MHz; outputs follow detected
// falling BCLK within 60..80ns plus IO delay (<162.76ns half bit nominal).
// This is a slave transmitter: bclk/lrclk are INPUTS, never driven here.
module i2s_codec_master(input wire clk,rst,bclk,lrclk,
 input wire signed [15:0] pcm,
 output reg sdata,sample_tick,output reg clocks_ok);
 reg [3:0] bs;
 reg [1:0] ls;
 wire falling=bs[3] && !bs[2];
 reg prev_lr,seen;
 reg [4:0] bits_left;
 reg [15:0] shift,left_hold,right_hold;
 reg [6:0] edges;
 reg [3:0] stable_frames;
 reg [15:0] period_count;
 always @(posedge clk) begin
  if(rst) begin
   bs<=0;ls<=0;prev_lr<=1;seen<=0;bits_left<=0;shift<=0;
   left_hold<=0;right_hold<=0;sdata<=0;sample_tick<=0;clocks_ok<=0;
   edges<=0;stable_frames<=0;period_count<=0;
  end else begin
   bs<={bs[2:0],bclk};ls<={ls[0],lrclk};sample_tick<=0;
   if(period_count!=65535) period_count<=period_count+1'b1;
   if(period_count>=2000) begin clocks_ok<=0;stable_frames<=0;end
   if(falling) begin
    if(edges!=127) edges<=edges+1'b1;
    if(ls[1]!=prev_lr) begin
     prev_lr<=ls[1];sdata<=0;bits_left<=16;
     if(!ls[1]) begin
      left_hold<=pcm;right_hold<=pcm;shift<=pcm;sample_tick<=1;
      if(seen && edges==63 && period_count>=1038 && period_count<=1045) begin
       if(stable_frames<8) stable_frames<=stable_frames+1'b1;
       if(stable_frames>=7) clocks_ok<=1;
      end else begin clocks_ok<=0;stable_frames<=0;end
      seen<=1;edges<=0;period_count<=0;
     end else shift<=right_hold;
    end else if(bits_left!=0) begin
     sdata<=shift[15];shift<={shift[14:0],1'b0};bits_left<=bits_left-1'b1;
    end else sdata<=0;
   end
  end
 end
endmodule
