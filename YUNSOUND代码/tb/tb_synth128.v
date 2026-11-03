`timescale 1ns/1ps
// Self-checking test. Uses only mathematical DDS inputs; no audio recordings.
module tb_synth128;
 reg clk=0; always #10 clk=~clk;
 reg rst=1, sample_tick=0, cmd_valid=0;
 reg [1:0] cmd_op=0, cmd_wave=0;
 reg [6:0] cmd_voice=0;
 reg [31:0] cmd_step=0;
 reg [7:0] cmd_gain=48;
 reg [15:0] cmd_attack=65535, cmd_decay=256, cmd_sustain=65535, cmd_release=65535;
 wire cmd_ready, sample_valid, overrun;
 wire signed [15:0] sample;
 wire [127:0] active;
 synth32_engine dut(clk,rst,sample_tick,cmd_valid,cmd_op,cmd_voice,cmd_step,
  cmd_wave,cmd_gain,cmd_attack,cmd_decay,cmd_sustain,cmd_release,
  cmd_ready,sample,sample_valid,active,overrun);
 integer cycles=0, render_start=0, frames=0;
 always @(posedge clk) begin
  cycles=cycles+1;
  if(sample_tick && !dut.busy) render_start=cycles;
  #1;
  if(sample_valid) begin
   if(cycles-render_start!=768) begin
    $display("FAIL latency %0d expected768",cycles-render_start); $fatal;
   end
   frames=frames+1;
  end
 end
 task send;
  input [1:0] op;
  input [6:0] voice;
  input [31:0] freq_step;
  begin
   @(negedge clk);
   cmd_valid=1; cmd_op=op; cmd_voice=voice; cmd_step=freq_step;
   while(!cmd_ready) @(negedge clk);
   @(posedge clk); #1;
   @(negedge clk); cmd_valid=0;
  end
 endtask
 task render;
  integer waited;
  begin
   @(negedge clk); sample_tick=1;
   @(negedge clk); sample_tick=0; waited=0;
   while(!sample_valid) begin
    @(negedge clk); waited=waited+1;
    if(waited>1000) begin $display("FAIL missed render deadline"); $fatal; end
   end
  end
 endtask
 task clear_reset;
  begin
   @(negedge clk); rst=1; sample_tick=0; cmd_valid=0;
   repeat(4) @(negedge clk);
   rst=0;
  end
 endtask

 integer i,j,n,bin_index,nonzero_samples; integer fd;
 integer pcm[0:2047];
 reg [31:0] old_phase, new_step;
 reg [15:0] old_env;
 real re,im,amp,min_amp,max_amp,angle,neighbor_re,neighbor_im,neighbor_amp;
 localparam real PI=3.14159265358979323846;
 initial begin
  repeat(5) @(negedge clk); rst=0;
  render;
  if(sample!==0 || active!==0 || overrun) begin $display("FAIL reset silence"); $fatal; end

  // Every voice receives its own frequency, phase and full ADSR state.
  // Bins 9,12,...102 over 2048 samples: 210.94 Hz ... 2390.63 Hz at 48 kHz.
  for(i=0;i<128;i=i+1) send(0,i,(9+3*i)*32'd2097152);
  repeat(64) render;
  nonzero_samples=0;
  for(n=0;n<2048;n=n+1) begin
   render;
   pcm[n]=$signed(sample); if(sample==32767 || sample==-32768)$fatal(1,"clipping");
   if(sample!=0) nonzero_samples=nonzero_samples+1;
   if(active!==128'hffffffffffffffffffffffffffffffff || overrun) begin
    $display("FAIL voices not all active at sample %0d active=%h",n,active); $fatal;
   end
   // Nominal 48k frame spacing at a 50MHz fabric clock (rounded to 1042).
   repeat(272) @(negedge clk);
  end
  if(nonzero_samples<1500) begin $display("FAIL mixed output mostly silent"); $fatal; end
  fd=$fopen("instrument128_fx/sim/spectrum128.csv","w");$fdisplay(fd,"bin,hz,amplitude,adjacent_amplitude");min_amp=1000000.0; max_amp=0.0;
  for(i=0;i<128;i=i+1) begin
   re=0.0; im=0.0; neighbor_re=0.0; neighbor_im=0.0; bin_index=9+3*i;
   for(n=0;n<2048;n=n+1) begin
    angle=2.0*PI*bin_index*n/2048.0;
    re=re+pcm[n]*$cos(angle); im=im-pcm[n]*$sin(angle);
    angle=2.0*PI*(bin_index+1)*n/2048.0;
    neighbor_re=neighbor_re+pcm[n]*$cos(angle);
    neighbor_im=neighbor_im-pcm[n]*$sin(angle);
   end
   amp=2.0*$sqrt(re*re+im*im)/2048.0;
   neighbor_amp=2.0*$sqrt(neighbor_re*neighbor_re+neighbor_im*neighbor_im)/2048.0;
   if(amp<150.0 || neighbor_amp>amp*0.1) begin
    $display("FAIL oscillator %0d peak=%f adjacent=%f",i,amp,neighbor_amp); $fatal;
   end
    $fdisplay(fd,"%0d,%f,%f,%f",bin_index,bin_index*48000.0/2048,amp,neighbor_amp); if(amp<min_amp) min_amp=amp;
   if(amp>max_amp) max_amp=amp;
  end
  $fclose(fd);$display("PASS 128 independent nonzero spectral sine peaks, amplitudes %0.2f..%0.2f, 768-cycle render",min_amp,max_amp);

  // Live pitch and timbre edits do not restart phase/envelope.
  old_phase=dut.phase[7]; old_env=dut.env[7]; new_step=32'd45678901;
  send(2,7,new_step); render;
  if(dut.phase[7]!==old_phase+new_step || dut.env[7]!==old_env) begin
   $display("FAIL pitch discontinuity"); $fatal;
  end
  old_phase=dut.phase[7]; cmd_wave=2; send(3,7,0); render;
  if(dut.phase[7]!==old_phase+new_step || dut.env[7]!==old_env || dut.wave_mode[7]!==2) begin
   $display("FAIL parameter update restarted voice"); $fatal;
  end
  cmd_wave=0;
  for(i=0;i<128;i=i+1) send(1,i,0);
  render;
  if(active!==0 || sample!==0) begin $display("FAIL release/silence"); $fatal; end

  // A NOTE_ON followed by NOTE_OFF before the sample must not disappear.
  send(0,4,32'd89478485); send(1,4,0);
  render;
  if(!active[4] || dut.env[4]!==16'hffff || sample==0) begin
   $display("FAIL short event lost"); $fatal;
  end
  render;
  if(active!==0 || sample!==0) begin $display("FAIL short event failed to release"); $fatal; end

  // Command at sample boundary is backpressured and applies only next frame.
  @(negedge clk); sample_tick=1; cmd_valid=1; cmd_op=0; cmd_voice=31; cmd_step=89478485;
  #1;
  if(cmd_ready) begin $display("FAIL boundary command was accepted"); $fatal; end
  @(negedge clk); sample_tick=0;
  while(!sample_valid) @(negedge clk);
  if(active!==0 || sample!==0) begin $display("FAIL boundary command leaked into frame"); $fatal; end
  // Keep the command stable through the first subsequent ready edge.
  @(posedge clk); #1;
  @(negedge clk); cmd_valid=0;
  render;
  if(!active[31] || sample==0) begin $display("FAIL backpressured NOTE_ON lost"); $fatal; end

  // A held NOTE_OFF arriving during rendering must not modify later voices.
  @(negedge clk); sample_tick=1;
  @(negedge clk); sample_tick=0;
  repeat(40) @(negedge clk);
  cmd_valid=1; cmd_op=1; cmd_voice=31;
  if(cmd_ready) begin $display("FAIL busy command ready"); $fatal; end
  while(!sample_valid) @(negedge clk);
  if(!active[31]) begin $display("FAIL incoherent mid-frame NOTE_OFF"); $fatal; end
  @(posedge clk); #1;
  @(negedge clk); cmd_valid=0;
  render;
  if(active!==0 || sample!==0 || overrun) begin $display("FAIL busy command release"); $fatal; end
  $display("PASS continuous pitch, timbre, release, short event, boundary and mid-render command handshake");

  // Exercise attack, decay, sustain and release with finite slopes.
  cmd_attack=16384; cmd_decay=8192; cmd_sustain=32768; cmd_release=8192;
  send(0,0,32'd89478485);
  for(i=1;i<=3;i=i+1) begin render; if(dut.env[0]!==i*16384) $fatal; end
  render; if(dut.env[0]!==65535) $fatal;
  repeat(4) render;
  if(dut.env[0]!==32768 || dut.state[0]!==3) begin $display("FAIL decay/sustain"); $fatal; end
  send(1,0,0);
  for(i=3;i>=0;i=i-1) begin render; if(dut.env[0]!==i*8192) $fatal; end
  if(active!==0) $fatal;
  $display("PASS ADSR slopes and independent state");

  // An early sample pulse is explicitly detected, not allowed to corrupt render.
  @(negedge clk); sample_tick=1;
  @(negedge clk); sample_tick=0;
  repeat(8) @(negedge clk);
  sample_tick=1;
  @(negedge clk); sample_tick=0;
  if(!overrun) begin $display("FAIL missing overrun flag"); $fatal; end
  while(!sample_valid) @(negedge clk);
  clear_reset; render;
  if(overrun || active!==0 || sample!==0) $fatal;
  $display("PASS overrun diagnostic and reset recovery");
  $display("PASS tb_synth128 all checks (%0d frames)",frames);
  $finish;
 end
 initial begin #100000000; $display("FAIL global timeout"); $fatal; end
endmodule
