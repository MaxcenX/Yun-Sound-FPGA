`timescale 1ns/1ps
module tb_split_integration;
 reg clk=0;always #10 clk=~clk;
 tri1 ts,td,cs,cd,as,ad;
 wire unused_tx;
 wire mc,sd,lr,lt,dio,sc,rc,dg;
 reg connected=1;reg [15:0] vx=2960,vy=2960,vp=7200;
 reg [11:0] touch=0;reg tick=0;integer frame_counter=0;
 ads_core dut(clk,3'b111,1'b1,ts,td,cs,cd,mc,1'b0,1'b0,sd,lr,lt,dio,sc,rc,dg,as,ad,1'b1,unused_tx,,,);
 ads1115_model #(.CONVERSION_NS(10000)) model(as,ad,connected,7'h48,vx,vy,vp,1'b0,1'b0);
 reg key_connected=1;
 mpr121_model keys(ts,td,key_connected,7'h5a,{4'b0,touch});
 defparam dut.sensor.I2C_Q=5,dut.sensor.POWER_WAIT=100,dut.sensor.RESET_WAIT=100,dut.sensor.SETTLE_WAIT=100,dut.sensor.POLL_WAIT=500,dut.sensor.RETRY_WAIT=500;
 defparam dut.reader.I2C_Q=5;
 defparam dut.reader.POWER_WAIT=100;
 defparam dut.reader.CONVERT_WAIT=500;
 defparam dut.reader.RETRY_WAIT=1000;
 defparam dut.controls.ARM_WAIT=16;
 defparam dut.xcontrol.CAL_SAMPLES=4;
 defparam dut.ycontrol.CAL_SAMPLES=4;
 always @(negedge clk) begin
  frame_counter=(frame_counter==1041)?0:frame_counter+1;
  tick=(frame_counter==0);
 end
 task groups;
 input integer n;integer i;
 begin for(i=0;i<n;i=i+1)begin @(posedge dut.av);repeat(40) @(negedge clk);end end
 endtask
 reg [31:0] before_step,after_step;
 always @(dut.sensor.state) $display("TRACE reader t=%0t state=%0d",$time,dut.sensor.state);
 initial begin
  $display("TRACE start");
  force dut.power_count=0;repeat(5) @(negedge clk);force dut.power_count=65535;
  $display("TRACE reset released");
  force dut.init_done=1;force dut.init_error=0;force dut.clocks_ok=1;
  wait(dut.sensor_ready);
  force dut.sample_tick=tick;
  $display("PROGRESS initialization/recovery"); groups(8);
  wait(dut.armed);
  if(!dut.calibrated || dut.cx!=740 || dut.cy!=740)$fatal(1,"center calibration");
  touch=12'h891;groups(4);
  if(dut.synth.step[0]!=23409859 || dut.synth.gain[12]!=8)$fatal(1,"neutral note");
  vx=7200;vp=0;groups(14);
  if(dut.mx!=64 || dut.my!=0 || dut.pressure_smooth!=4095)$fatal(1,"X/P mapping %d %d %d",dut.mx,dut.my,dut.pressure_smooth);
  if(dut.synth.gain[0]!=220 || dut.synth.gain[12]!=39 || dut.synth.step[0]<=23409859)$fatal(1,"X/pressure not combined");
  vy=7200;groups(14);
  force dut.ycontrol.lfo=32'h00000000;
  repeat(4000) @(negedge clk);before_step=dut.synth.step[0];
  force dut.ycontrol.lfo=32'h7f800000;
  repeat(4000) @(negedge clk);after_step=dut.synth.step[0];
  if(before_step>=after_step || dut.synth.gain[12]!=39 || dut.mx!=64)$fatal(1,"combined X Y P");
  release dut.ycontrol.lfo;
  vx=2960;vy=2960;vp=7200;groups(14);
  if(dut.mx!=0 || dut.my!=0 || dut.pressure_smooth!=0)$fatal(1,"neutral recovery");
  if(dut.overrun)$fatal(1,"render overrun");
  vx=25600;vy=26400;vp=25600;groups(14);
  if(!dut.play || !dut.calibrated || dut.mx!=64 || dut.pressure_smooth!=0)$fatal(1,"3.2/3.3V should not mute");
  force dut.page=1;#100;if(dut.mv!=3200)$fatal(1,"3200mV display");
  force dut.page=2;#100;if(dut.mv!=3300)$fatal(1,"3300mV display");release dut.page;
  vy=2960;vp=7200;
  vx=26480;groups(2);
  if(dut.play || dut.safe_sample!=0 || dut.digits[31:24]!=8'he5)$fatal(1,"range mute");
  vx=2960;groups(8);touch=0;groups(2);wait(dut.armed);
  connected=0;wait(dut.adc_fault);repeat(10) @(negedge clk);
  if(dut.play || dut.safe_sample!=0)$fatal(1,"ADC NACK mute");
  connected=1;groups(8);wait(dut.armed);
  touch=1;groups(4);if(dut.active==0)$fatal(1,"restart");
  $display("PROGRESS keyboard fault test"); key_connected=0;wait(dut.sensor_fault);repeat(10) @(negedge clk);
  if(dut.play || dut.safe_sample!=0 || dut.digits[31:24]!=8'he6)$fatal(1,"keyboard fault/E6");
  touch=0;key_connected=1;wait(dut.sensor_ready);wait(dut.armed);
  touch=1;groups(4);if(dut.active==0)$fatal(1,"keyboard restart");
  $display("PASS 3.3V range, display, endpoint clamp and ADS integration: actual I2C model through calibration, 4-key chord, X bend + Y vibrato + inverted pressure concurrently, neutral recovery, range/NACK mute/recovery; separate ADS/MPR models, keyboard E6 mute/recovery; injected codec states");$finish;
 end
 initial begin
  repeat(80) begin #1000000;
   $display("TRACE t=%0t sensor=%0d fault=%0d state=%0d adc=%0d calibrated=%0d armed=%0d",$time,dut.sensor_ready,dut.sensor_fault,dut.sensor.state,dut.adc_ready,dut.calibrated,dut.armed);
  end
  $fatal(1,"integration timeout");
 end
endmodule


