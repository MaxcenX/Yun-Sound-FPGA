`timescale 1ns/1ps
module tb_timbre_headroom;
reg clk=0,rst=1,tick=0;always #10 clk=~clk;
reg [11:0] touch=0;reg [1:0] timbre=0;
wire cv,cr,armed,sv,overrun;wire [1:0] op,wave;wire [6:0] voice;
wire [31:0] step;wire [7:0] gain;wire [15:0] attack,decay,sustain,rel;
wire signed [15:0] pcm;wire [127:0] active;
performance_control #(.ARM_WAIT(1)) ctrl(clk,rst,touch,2'd0,timbre,17'd65536,1'b1,12'd4095,cr,cv,op,voice,step,wave,gain,attack,decay,sustain,rel,armed,2'd1);
synth32_engine synth(clk,rst,tick,cv,op,voice,step,wave,gain,attack,decay,sustain,rel,cr,pcm,sv,active,overrun);
integer frames,peak,n,t,fd,i,total,bound;integer gains[0:127];reg [127:0] seen=0;
always @(posedge clk) if(!rst && cv && cr)begin
 if(op==0 || op==3)begin gains[voice]=gain;seen[voice]=1;end
end
always @(negedge clk)if(!rst && sv)begin
 frames=frames+1;
 if(pcm==32767 || pcm==-32768 || overrun)$fatal(1,"clipping/overrun");
 if(pcm>peak)peak=pcm;if(-pcm>peak)peak=-pcm;
 if(fd)$fdisplay(fd,"%0d,%0d,%0d",t,frames,$signed(pcm));
end
initial begin
 fd=$fopen("instrument128_fx/sim/timbre_chords.csv","w");$fdisplay(fd,"timbre,frame,pcm");
 for(t=0;t<4;t=t+1)begin
 rst=1;touch=0;tick=0;timbre=t;seen=0;frames=0;peak=0;
 for(i=0;i<128;i=i+1)gains[i]=0;
 repeat(5)@(negedge clk);rst=0;wait(armed);@(negedge clk);touch=12'hfff;
 for(n=0;n<1024;n=n+1)begin tick=1;@(negedge clk);tick=0;repeat(1041)@(negedge clk);end
 if(seen!=={128{1'b1}} || frames!=1024 || peak<1000)$fatal(1,"missing output");
 total=0;for(i=0;i<128;i=i+1)total=total+gains[i];
 // Each sine <=16384, full envelope, all partials maximally coherent.
 // Allow two PCM codes per voice for fixed-point rounding; all effects <=1.5x.
 bound=(total*64+256)/16;
 if(bound*3/2>=30000)$fatal(1,"insufficient coherent effects headroom");
 if(t==0 && gains[12]<=60)$fatal(1,"pressure scaling lost");
 if(t==2 && gains[24]<4*gains[12])$fatal(1,"reed odd spectrum lost");
 if(t==3 && gains[12]!=0)$fatal(1,"sine reference has partials");
 $display("PASS timbre=%0d twelve keys max pressure: peak=%0d coherent_dry_bound=%0d effects_bound=%0d",t,peak,bound,bound*3/2);
 end
 $fclose(fd);$finish;
end
endmodule
