`timescale 1ns/1ps
// Note/beat events only, no audio recording. User generates every sound live.
module lesson_guide(input wire clk,rst,enable,sample_tick,input wire [11:0] touch,
 output reg [3:0] target,output wire correct,beat);
 reg [3:0] index;reg wait_release;reg [14:0] beat_count;
 assign correct=enable && touch==(12'b1<<target);
 assign beat=beat_count<4800;
 always @* case(index)
  0,1,13:target=0;2,3,6:target=7;4,5:target=9;
  7,8:target=5;9,10:target=4;11,12:target=2;default:target=0;
 endcase
 always @(posedge clk) begin
  if(rst || !enable) begin index<=0;wait_release<=0;beat_count<=0;end
  else begin
   if(sample_tick) beat_count<=(beat_count==23999)?0:beat_count+1'b1;
   if(correct) wait_release<=1;
   if(wait_release && touch==0) begin wait_release<=0;index<=(index==13)?0:index+1'b1;end
  end
 end
endmodule
