`timescale 1ns/1ps
module tb_latency128;
reg clk=0,rst=1,b=1,lr=1;
always #10 clk=~clk;
always #162.760417 b=~b;
integer slot=63;
always @(negedge b) begin slot=(slot+1)%64; if(slot==0)lr=0; if(slot==32)lr=1; end
reg [11:0] touch=0; reg [1:0] timbre=0,octave=0;
wire tick,ok,sd,ready,sv,wv,overrun,valid,armed;
wire [1:0] op,wave;wire [6:0] voice;wire [31:0] step;wire [127:0] active;
wire [7:0] gain;wire [15:0] attack,decay,sustain,release_rate;
wire signed [15:0] pcm,wet;
performance_control #(.ARM_WAIT(4)) control(clk,rst,touch,2'd0,timbre,17'd65536,1'b1,12'd4095,
 ready,valid,op,voice,step,wave,gain,attack,decay,sustain,release_rate,armed,octave);
synth32_engine synth(clk,rst,tick,valid,op,voice,step,wave,gain,attack,decay,sustain,release_rate,ready,pcm,sv,active,overrun);
audio_effects echo(clk,rst,sv,pcm,2'd0,wet,wv);
i2s_codec_master tx(clk,rst,b,lr,wet,sd,tick,ok);
integer vi; integer trial=0,fh,k,t,o,p,phase_cycles;reg testing=0;
realtime t0,tcmd,taffected,tnonzero,tthreshold,t_allcmd;
reg render_tag=0,latched_tag=0;reg [127:0] seen_on=0,expected;
reg [15:0] left=0,right=0;integer magnitude; integer peak=0;
// Observe real handshakes, no forced DUT state or shortened audio clock.
always @(posedge clk) begin
 if(rst) begin render_tag=0;latched_tag=0;seen_on=0; end
 else begin
  if(testing && valid && ready && op==0) begin
   if(tcmd==0)tcmd=$realtime;
   seen_on[voice]=1;
   if((seen_on & expected)==expected && t_allcmd==0)t_allcmd=$realtime;
  end
  if(testing && tick && synth.pending!=0) render_tag=1;
  // A tag becomes available only after this render and echo pipeline finish.
  if(testing && tx.falling && tx.ls[1]!=tx.prev_lr && !tx.ls[1])
   latched_tag=render_tag && !synth.busy && wv_seen;
 end
end
reg wv_seen=0;
always @(negedge clk) begin if(rst)wv_seen=0;else if(render_tag && wv)wv_seen=1;end
// Decode the actual serial output; stop timestamps after BOTH 16-bit words.
always @(posedge b) begin
 if(slot==0)left=0;
 if(slot>=1 && slot<=16)left={left[14:0],sd};
 if(slot==32)right=0;
 if(slot>=33 && slot<=48)right={right[14:0],sd};
 if(slot==48 && testing) begin
  if(left!==tx.right_hold)$fatal(1,"Serial decoder mismatch"); if(left!==right)$fatal(1,"Stereo mismatch");
  if(latched_tag && taffected==0)taffected=$realtime;
  if(left!=0 && tnonzero==0)tnonzero=$realtime;
  magnitude=$signed(left);if(magnitude<0)magnitude=-magnitude; if(magnitude>peak)peak=magnitude;
  if(magnitude>=32 && tthreshold==0)tthreshold=$realtime;
 end
end
initial begin
 fh=$fopen("instrument128_fx/sim/latency.csv","w");
 $fdisplay(fh,"trial,key,timbre,octave,phase_cycles,first_command_us,all_commands_us,affected_pair_us,nonzero_pair_us");
 // 12 single keys + all-12 chord, 3 timbres, 3 octaves, 117 distributed input phases.
 for(k=0;k<13;k=k+1)for(t=0;t<4;t=t+1)for(o=0;o<3;o=o+1)for(p=0;p<1;p=p+1) begin
  testing=0;rst=1;touch=0;timbre=t;octave=o;
  repeat(5)@(negedge clk);rst=0;wait(ok && armed);
  @(negedge lr);phase_cycles=(k*83+t*317+o*193)%1042;repeat(phase_cycles)@(negedge clk);
  @(negedge clk);t0=$realtime;tcmd=0;taffected=0;tnonzero=0;tthreshold=0;t_allcmd=0;
  expected=0;
  for(vi=0;vi<128;vi=vi+1)if(k==12 || vi%12==k)expected[vi]=1;

  testing=1;touch=(k==12)?12'hfff:(12'h1<<k);
  fork begin wait(tnonzero!=0 && t_allcmd!=0 && taffected!=0); end begin #2000000; $fatal(1,"Trial timeout trial=%d cmd=%f all=%f affected=%f nonzero=%f thresh=%f left=%h seen=%h peak=%d pcm=%d gain=%d env=%d",trial,tcmd,t_allcmd,taffected,tnonzero,tthreshold,left,seen_on,peak,pcm,synth.gain_smooth[0],synth.env[0]); end join_any disable fork;
  if(overrun || (tnonzero-t0)>1000000 || (taffected-t0)>150000)$fatal(1,"Latency/overrun assertion");
  $fdisplay(fh,"%0d,%0d,%0d,%0d,%0d,%0.3f,%0.3f,%0.3f,%0.3f",trial,k,t,o,phase_cycles,
   (tcmd-t0)/1000,(t_allcmd-t0)/1000,(taffected-t0)/1000,(tnonzero-t0)/1000);
  $fflush(fh);trial=trial+1;
  if(trial%13==0)$display("Completed %0d trials",trial);
 end
 $fclose(fh);$display("PASS %0d trials",trial);$finish;
end
initial begin #3000000000;$fatal(1,"Timeout");end
endmodule






