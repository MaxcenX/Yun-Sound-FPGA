`timescale 1ns/1ps
module joystick_control #(
 parameter MODE=0, CAL_SAMPLES=64, DEBOUNCE_CYCLES=1000000
)(input wire clk,rst,enable,adc_valid,input wire [13:0] adc_value,
 input wire k_n,sample_tick,
 output reg calibrated,sounding,output reg [13:0] center,
 output reg cmd_valid,output reg [1:0] cmd_op,output wire [31:0] cmd_step, output wire signed [8:0] modulation);
 assign modulation=mod_index;
 reg [1:0] ks;
 reg stable_k,released;
 integer debounce_count,cal_count;
 reg [21:0] cal_sum;
 reg [13:0] cal_min,cal_max;
 reg signed [8:0] position;
 reg [31:0] lfo;
 integer diff,mag,target,error_pos,lfo_triangle,depth,mod_index;
 wire [7:0] lookup_index=mod_index+64;
 pitch_lut #(.MODE(MODE)) lut(lookup_index,cmd_step);
 always @* begin
  lfo_triangle=lfo[31] ? (255-{1'b0,lfo[30:23]}) : {1'b0,lfo[30:23]};
  lfo_triangle=lfo_triangle-128;
  depth=(position<0)?-position:position;
  if(MODE==0) mod_index=position;
  else mod_index=(lfo_triangle*depth) >>> 7;
 end
 always @(posedge clk) begin
  if(rst || !enable) begin
   calibrated<=0;sounding<=0;center<=0;cmd_valid<=0;cmd_op<=0;
   ks<=3;stable_k<=1;released<=0;debounce_count<=0;
   cal_count<=0;cal_sum<=0;cal_min<=16383;cal_max<=0;position<=0;lfo<=0;
  end else begin
   ks<={ks[0],k_n};cmd_valid<=0;
   if(sample_tick) lfo<=lfo+32'd447392; // approximately 5Hz at 48kHz
   if(adc_valid) begin
    if(!calibrated) begin
     if(adc_value<256 || adc_value>1536) begin
      cal_count<=0;cal_sum<=0;cal_min<=16383;cal_max<=0;
     end else if(cal_count==CAL_SAMPLES-1) begin
      // Motion/noise during calibration requires a fresh, stable window.
      if((cal_max-cal_min)<=48 && adc_value+48>=cal_max && adc_value<=cal_min+48) begin
       center<=(cal_sum+adc_value)/CAL_SAMPLES;calibrated<=1;position<=0;
      end
      cal_count<=0;cal_sum<=0;cal_min<=16383;cal_max<=0;
     end else begin
      cal_count<=cal_count+1;cal_sum<=cal_sum+adc_value;
      if(adc_value<cal_min) cal_min<=adc_value;
      if(adc_value>cal_max) cal_max<=adc_value;
     end
    end else begin
     diff=$signed({1'b0,adc_value})-$signed({1'b0,center});
     // ~12mV neutral dead band. Asymmetric slopes match the measured 0.37V center.
     if(diff>24) target=(diff-24)/16;
     else if(diff< -24) begin mag=-diff-24;target=-((mag*90) >> 10);end
     else target=0;
     if(target>64) target=64;
     if(target< -64) target=-64;
     error_pos=target-position;
     if(error_pos>=4 || error_pos<=-4) position<=position+(error_pos/4);
     else if(error_pos>0) position<=position+1'b1;
     else if(error_pos<0) position<=position-1'b1;
    end
   end
   if(ks[1]==stable_k) begin
    debounce_count<=0;
    if(calibrated && stable_k) released<=1;
   end else if(debounce_count>=DEBOUNCE_CYCLES-1) begin
    debounce_count<=0;stable_k<=ks[1];
    if(!ks[1] && calibrated && released) begin
     sounding<=!sounding;cmd_valid<=1;cmd_op<=sounding?2'd1:2'd0;
    end
   end else debounce_count<=debounce_count+1;
   if(sample_tick && sounding) begin
    // Key edges take priority over continuous pitch updates below.
    if(!(ks[1]!=stable_k && debounce_count>=DEBOUNCE_CYCLES-1 && !ks[1] && calibrated && released)) begin
     cmd_valid<=1;cmd_op<=2;
    end
   end
  end
 end
endmodule


