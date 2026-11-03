`timescale 1ns/1ps
module tb_testmode128;
reg clk=0,rst=1,tick=0;always #10 clk=~clk;
wire cv,cr,armed,sv,overrun;wire [1:0] op,wave;wire [6:0] voice;
wire [31:0] step;wire [7:0] gain;wire [15:0] attack,decay,sustain,rel;
wire signed [15:0] pcm;wire [127:0] active;
performance_control #(.ARM_WAIT(1)) ctrl(clk,rst,12'd0,2'd2,2'd0,17'd65536,1'b1,12'd0,cr,cv,op,voice,step,wave,gain,attack,decay,sustain,rel,armed,2'd1);
synth32_engine synth(.clk(clk),.rst(rst),.sample_tick(tick),.cmd_valid(cv),.cmd_ready(cr),.cmd_op(op),.cmd_voice(voice),.cmd_step(step),.cmd_wave(wave),.cmd_gain(gain),.cmd_attack(attack),.cmd_decay(decay),.cmd_sustain(sustain),.cmd_release(rel),.sample(pcm),.sample_valid(sv),.active(active),.overrun(overrun));
integer frames=0,peak=0,n=0;reg [127:0] started=0;
always @(posedge clk) if(!rst && cv && cr)begin
 if(gain!=32 || step!=((32'd64+voice*32'd19)<<18))$fatal(1,"test-mode command");
 if(op==0)started[voice]=1;
end
always @(negedge clk)if(!rst && sv)begin
 frames=frames+1;
 if(pcm==32767 || pcm==-32768 || overrun)$fatal(1,"clipping/overrun");
 if(pcm>peak)peak=pcm;if(-pcm>peak)peak=-pcm;
end
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(n=0;n<4096;n=n+1)begin tick=1;@(negedge clk);tick=0;repeat(1041)@(negedge clk);end
 if(started!=={128{1'b1}} || active!=={128{1'b1}} || frames!=4096 || peak<1000)$fatal(1,"voices/output missing");
 $display("PASS production 128-tone test mode: all independent frequency commands, gain32, 4096 frames, no clipping/overrun, peak=%d",peak);$finish;
end
endmodule
