`timescale 1ns/1ps
module tb_pressure_held_audio;
reg clk=0,rst=1,tick=0;always #10 clk=~clk;
reg [11:0] touch=0,pressure=0;
wire cv,cr,armed,sv,overrun;wire [1:0] op,wave;wire [6:0] voice;
wire [31:0] step;wire [7:0] gain;wire [15:0] attack,decay,sustain,rel;
wire signed [15:0] pcm;wire [127:0] active;
performance_control #(.ARM_WAIT(1)) ctrl(clk,rst,touch,2'd0,2'd3,17'd65536,1'b1,pressure,cr,cv,op,voice,step,wave,gain,attack,decay,sustain,rel,armed,2'd1);
synth32_engine synth(clk,rst,tick,cv,op,voice,step,wave,gain,attack,decay,sustain,rel,cr,pcm,sv,active,overrun);
integer k,peak,rest_peak,full_peak,frames,collect=0,last_gain=0;
always @(negedge clk)if(!rst && sv)begin
 if(overrun || pcm==32767 || pcm==-32768)$fatal(1,"clip/overrun");
 if(collect)begin
 if(pcm>peak)peak=pcm;if(-pcm>peak)peak=-pcm;
 frames=frames+1;
 end
end
task render;
input integer count;
begin for(k=0;k<count;k=k+1)begin tick=1;@(negedge clk);tick=0;repeat(1041)@(negedge clk);end end
endtask
initial begin
 repeat(5)@(negedge clk);rst=0;wait(armed);@(negedge clk);touch=1;
 // Compare sustain against sustain, not attack/decay against sustain.
 render(700);peak=0;frames=0;collect=1;render(256);collect=0;rest_peak=peak;
 pressure=4095;render(300);
 if(synth.gain[0]!=220)$fatal(1,"held root gain not updated to full");
 peak=0;frames=0;collect=1;render(256);collect=0;full_peak=peak;
 if(full_peak<rest_peak*3 || full_peak>rest_peak*4)$fatal(1,"audio dynamics insufficient rest=%0d full=%0d",rest_peak,full_peak);
 pressure=0;render(300);
 if(synth.gain[0]!=68)$fatal(1,"held root not returned to rest");
 if(!active[0])$fatal(1,"pressure released held note");
 touch=0;render(512);if(active[0])$fatal(1,"note off failed");
 $display("PASS held sine audio rest_peak=%0d full_peak=%0d; gain rises and falls without new key press; note off works",rest_peak,full_peak);
 $finish;
end
endmodule
