`timescale 1ns/1ps
module ads_core #(parameter TEST_ONLY=0,DIAGNOSTIC=0,PURE=0)(
 input wire clk_50m,input wire [2:0] key_n,input wire joy_k_n,
 inout wire touch_scl,touch_sda,aud_i2c_scl,aud_i2c_sda,
 output wire i2s_mclk,input wire i2s_bclk,i2s_daclrc,output wire i2s_dacdat,
 output wire led_ready,led_touch,seg_dio,seg_sclk,seg_rclk,debug_gate,
 inout wire adc_scl,adc_sda,input wire bt_rx,output wire bt_tx,output wire led_sdi,led_sck,led_lat);
 reg [15:0] power_count=0;wire rst=!(&power_count);
 always @(posedge clk_50m) if(rst) power_count<=power_count+1'b1;
 reg [1:0] mdiv;reg [25:0] blink;
 always @(posedge clk_50m) if(rst) begin mdiv<=0;blink<=0;end
 else begin mdiv<=mdiv+1'b1;blink<=blink+1'b1;end
 assign i2s_mclk=mdiv[1];
 wire [1:0] timbre,ui_mode;wire [1:0] effect_mode; wire effect_on=|effect_mode;
 performance_ui ui(clk_50m,rst,key_n,timbre,effect_mode,ui_mode);
 wire remote_override;wire [1:0] remote_mode;
 wire [1:0] mode=TEST_ONLY?2'd2:(remote_override?(remote_mode==0?2'd0:2'd1):ui_mode);
 wire gated,pressed;
 assign gated=1'b0;assign pressed=1'b0;
 reg [1:0] old_mode;reg old_gate;
 always @(posedge clk_50m) if(rst) begin old_mode<=mode;old_gate<=0;end
 else begin old_mode<=mode;old_gate<=gated;end
 wire switching=(old_mode!=mode)||(old_gate!=gated);
 wire init_done,init_error,clocks_ok,sample_tick;wire [5:0] failed;wire [1:0] bus_error;
 codec_master_init init(clk_50m,rst,clocks_ok,aud_i2c_scl,aud_i2c_sda,
  init_done,init_error,failed,bus_error);
 wire [11:0] touch;wire sensor_ready,sensor_fault;wire [6:0] sensor_addr;
 mpr121_reader sensor(clk_50m,rst,touch_scl,touch_sda,touch,sensor_ready,sensor_fault,sensor_addr);
 wire [15:0] adc_x,adc_y,adc_p;wire av,adc_ready,adc_fault;wire [3:0] adc_error;
 ads1115_reader reader(clk_50m,rst,adc_scl,adc_sda,adc_x,adc_y,adc_p,av,adc_ready,adc_fault,adc_error);
 // Nominal 0..0.9V controls; accept up to 3.3V, clamp expression endpoints.
 wire range_ok=adc_x<=26400 && adc_y<=26400 && adc_p<=26400;
 wire adc_ok=adc_ready && !adc_fault && range_ok;
 wire [13:0] ax=adc_x>=7200?14'd1800:{1'b0,adc_x[14:2]},ay=adc_y>=7200?14'd1800:{1'b0,adc_y[14:2]};
 wire [11:0] pressure;
 ads_pressure_map pressure_mapper(clk_50m,rst,adc_ok,{1'b0,adc_p[14:2]},pressure);
 wire enable_expression=init_done && clocks_ok && !init_error && adc_ok;
 wire [6:0] xdepth,ydepth;
 wire cal_x,cal_y;wire [13:0] cx,cy;wire signed [8:0] mx,my;
 ads_axis #(.MODE(0)) xcontrol(clk_50m,rst,enable_expression,av,ax,sample_tick,cal_x,cx,mx,xdepth);
 ads_axis #(.MODE(1)) ycontrol(clk_50m,rst,enable_expression,av,ay,sample_tick,cal_y,cy,my,ydepth);
 wire calibrated=cal_x && cal_y;
 wire signed [11:0] bend={{3{mx[8]}},mx},vib={{3{my[8]}},my};
 wire signed [11:0] offset=(bend<<<2)+vib;
 wire [9:0] ratio_index=offset+12'sd320;wire [16:0] ratio;
 expression_ratio ratios(ratio_index,ratio);
 reg [11:0] pressure_smooth;integer pdiff;
 reg [3:0] pressure_delay;
 always @(posedge clk_50m) if(rst || !adc_ok) pressure_delay<=0;
 else pressure_delay<={pressure_delay[2:0],av};
 always @(posedge clk_50m) if(rst || !adc_ok) pressure_smooth<=0;
 else if(pressure_delay[3]) begin
  pdiff=$signed({1'b0,pressure})-$signed({1'b0,pressure_smooth});
  if(pdiff>=2 || pdiff<=-2) pressure_smooth<=pressure_smooth+(pdiff/2);
  else if(pdiff>0) pressure_smooth<=pressure_smooth+1'b1;
  else if(pdiff<0) pressure_smooth<=pressure_smooth-1'b1;
 end
 wire play=!DIAGNOSTIC && init_done && clocks_ok && !init_error && (mode==2 || (sensor_ready && !sensor_fault && adc_ok && calibrated));
 wire core_reset=rst || !play || switching;
 wire [11:0] effective_touch=(gated && !pressed)?12'd0:touch;
 wire [1:0] octave;
 wire cmd_valid,cmd_ready,armed;wire [1:0] cmd_op,cmd_wave;wire [6:0] cmd_voice;
 wire [31:0] cmd_step;wire [7:0] cmd_gain;wire [15:0] attack,decay,sustain,release_rate;
 performance_control #(.PURE(PURE)) controls(clk_50m,core_reset,effective_touch,mode,timbre,ratio,
  1'b1,pressure_smooth,cmd_ready,cmd_valid,cmd_op,cmd_voice,cmd_step,
  cmd_wave,cmd_gain,attack,decay,sustain,release_rate,armed,octave);
 wire signed [15:0] sample,wet;wire sample_valid,wet_valid;wire [127:0] active;wire overrun;
 synth32_engine synth(clk_50m,core_reset,sample_tick,cmd_valid,cmd_op,cmd_voice,cmd_step,
  cmd_wave,cmd_gain,attack,decay,sustain,release_rate,cmd_ready,sample,sample_valid,active,overrun);
 audio_effects echo(clk_50m,core_reset,sample_valid,sample,(mode==2?2'd0:effect_mode),wet,wet_valid);
 wire signed [15:0] safe_sample=play && !switching && !overrun?wet:16'sd0;
 i2s_codec_master tx(clk_50m,rst,i2s_bclk,i2s_daclrc,safe_sample,i2s_dacdat,sample_tick,clocks_ok);
 wire [1023:0] visual_wave,visual_xy;wire [255:0] visual_bands;wire [1:0] graph_select;wire [7:0] graph_stride,wave_meta;
 visual_telemetry graphics(clk_50m,rst,wet_valid,wet,sample,visual_wave,visual_bands,visual_xy,graph_stride,wave_meta);
 wire [3:0] target,target_octave;wire correct,beat,lesson_done,downloaded,upload_error;
 wire [11:0] remote_led_mask;wire remote_led_valid;
 wire [5:0] song_cursor;wire [6:0] song_length;
 score_ble lesson(clk_50m,rst,bt_rx,mode==1 && play && armed,sample_tick,touch,octave,
  bt_tx,remote_override,remote_mode,target,target_octave,correct,beat,
  lesson_done,song_cursor,song_length,downloaded,upload_error,
  visual_wave,visual_bands,visual_xy,mx[7:0],{1'b0,ydepth},pressure_smooth,
  {5'd0,play,calibrated,adc_ok},graph_select,graph_stride,remote_led_mask,remote_led_valid,wave_meta);
 wire [11:0] guided_led=remote_led_valid?remote_led_mask:(mode==1 && play && !lesson_done && target<12)?
  (12'b1<<target):touch;
 led595_driver guide_led(clk_50m,rst,guided_led,led_sdi,led_sck,led_lat);
 assign led_ready=DIAGNOSTIC?adc_ok:(play && armed?((mode==1)?beat:1'b1):blink[24]);
 assign led_touch=play && armed && ((mode==1)?correct:(|active));
 assign debug_gate=play && armed && ((mode==2)?1'b1:(|effective_touch));
 integer j;reg [7:0] count;reg [3:0] current_key;reg found;
 always @* begin
  count=0;current_key=15;found=0;
  for(j=0;j<128;j=j+1) count=count+active[j];
  for(j=0;j<12;j=j+1) if(touch[j] && !found) begin current_key=j;found=1;end
  if(mode==1) current_key=target;
 end
 wire [3:0] ct=count/10,co=count%10;
 wire [3:0] kt=(current_key==15)?4'hf:((current_key>=10)?4'd1:4'd0);
 wire [3:0] ko=(current_key==15)?4'hf:((current_key>=10)?current_key-4'd10:current_key);
 wire [3:0] mode_digit={2'd0,mode}+4'd1,timbre_digit={2'd0,timbre}+4'd1;

 display_page #(.DEFAULT_PAGE(1)) octave_button(clk_50m,rst,joy_k_n,octave);
 wire [1:0] page=DIAGNOSTIC?2'd1:2'd0;
 wire [3:0] octave_digit={2'b0,octave}+4'd3;
 wire [19:0] pprod=pressure_smooth*7'd100;
 wire [6:0] percent=(pprod+20'd2047)/12'd4095;
 wire [3:0] ph=percent/100,pt=(percent/10)%10,pu=percent%10;
 wire [15:0] selected_raw=page==1?adc_x:(page==2?adc_y:adc_p);
 // 125uV/code -> millivolts=code/8.
 wire [11:0] mv=selected_raw[14:3];
 wire [3:0] m3=mv/1000,m2=(mv/100)%10,m1=(mv/10)%10,m0=mv%10;
 wire [6:0] song_number={1'b0,song_cursor}+1'b1;
 wire [3:0] pos_t=song_number/10,pos_o=song_number%10;
 wire [3:0] goal_t=(target==15)?4'hf:((target>=10)?4'd1:4'd0);
 wire [3:0] goal_o=(target==15)?4'hf:((target>=10)?target-4'd10:target);
 // O G KK II MD: current/target octave, target key, event index, mode, done.
 wire [31:0] guide_digits={octave_digit,target_octave,goal_t,goal_o,pos_t,pos_o,
  (remote_mode==2?4'd2:4'd1),{3'b0,lesson_done}};
 wire [3:0] count_h=count/100,count_t=(count/10)%10,count_o=count%10;
 wire [31:0] normal_digits={octave_digit,timbre_digit,(mode==2?4'd0:{2'd0,effect_mode}),count_h,count_t,count_o,kt,ko};
 wire [31:0] measured_digits={{2'b0,page},m3,m2,m1,m0,ph,pt,pu};
 // Error prefix E, code:1 NACK,2 timeout,3 config,4 conversion,5 range.
 wire [3:0] shown_error=adc_fault?adc_error:(!range_ok?4'd5:4'd6);
 wire [31:0] digits=((mode!=2 || DIAGNOSTIC) && (adc_fault || (adc_ready && !range_ok) || sensor_fault))?{4'he,shown_error,24'hffffff}:
                       ((page==0)?((mode==1)?guide_digits:normal_digits):measured_digits);
 seg_display display(clk_50m,rst,digits,seg_dio,seg_sclk,seg_rclk);
endmodule

