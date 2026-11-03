`timescale 1ns/1ps
// 128 independent oscillators: 12 roots, harmonics 2..10 (12 each), harmonic 11 (8).
// Commands are held stable until the engine acknowledges cmd_ready.
module performance_control #(parameter PURE=0, ARM_WAIT=2500000)(
 input wire clk,rst,input wire [11:0] touch,input wire [1:0] mode,timbre,
 input wire [16:0] ratio,input wire pressure_enable,input wire [11:0] pressure,
 input wire cmd_ready,
 output reg valid,output reg [1:0] op,output reg [6:0] voice,
 output reg [31:0] step,output reg [1:0] wave,
 output reg [7:0] gain,output reg [15:0] attack,decay,sustain,release_rate,
 output reg armed,input wire [1:0] octave);
 reg [11:0] previous_touch;
 reg [1:0] key_octave[0:11];
 integer oi;
 always @(posedge clk) if(rst) begin
  previous_touch<=0;
  for(oi=0;oi<12;oi=oi+1) key_octave[oi]<=1;
 end else begin
  previous_touch<=touch;
  for(oi=0;oi<12;oi=oi+1)
   if(touch[oi] && !previous_touch[oi]) key_octave[oi]<=octave;
 end
 reg [127:0] sent;
 reg [1:0] voice_timbre[0:127];
 reg [6:0] scan;
 reg [2:0] state;
 reg alternate;
 reg desired;
 reg [31:0] base;
 reg [16:0] ratio_r;
 reg [48:0] product;
 integer arm_count,k;
 reg [3:0] key_index;
 reg [1:0] preset;
 reg [7:0] layer_gain;
 reg [3:0] harmonic;
 reg [7:0] spectral_gain;
 reg [8:0] pressure_scale, expressive_scale;
 reg [7:0] pressure_tail;
 reg [9:0] pressure_tail_scaled;
 reg [16:0] pressure_product;
 function [7:0] spectrum;
 input [1:0] tone; input [3:0] h;
 begin
 case(tone)
  0:case(h) // warm organ: fundamental and rounded even/odd harmonics
   1:spectrum=180;2:spectrum=48;3:spectrum=24;4:spectrum=12;
   5:spectrum=6;6:spectrum=3;7:spectrum=2;default:spectrum=1;
  endcase
  1:case(h) // plucked string: bright attack, upper partials decay sooner
   1:spectrum=150;2:spectrum=80;3:spectrum=40;4:spectrum=20;
   5:spectrum=10;6:spectrum=5;7:spectrum=3;8:spectrum=2;default:spectrum=1;
  endcase
  2:case(h) // reed: predominantly odd partials, clearly different from organ
   1:spectrum=180;2:spectrum=2;3:spectrum=64;4:spectrum=2;
   5:spectrum=32;6:spectrum=1;7:spectrum=16;8:spectrum=1;
   9:spectrum=8;10:spectrum=1;11:spectrum=4;default:spectrum=0;
  endcase
  default:spectrum=(h==1)?220:0;
 endcase
 end endfunction
 reg [31:0] octave_step;
 reg [1:0] selected_octave;
 function [31:0] note_step;
 input [3:0] key;
 begin case(key)
  0:note_step=23409859;1:note_step=24801882;2:note_step=26276679;
  3:note_step=27839171;4:note_step=29494575;5:note_step=31248413;
  6:note_step=33106541;7:note_step=35075158;8:note_step=37160835;
  9:note_step=39370534;10:note_step=41711627;11:note_step=44191930;
  default:note_step=23409859;
 endcase end endfunction
 always @* begin
  if(scan>=120) key_index=scan-120;
  else if(scan>=108) key_index=scan-108;
  else if(scan>=96) key_index=scan-96;
  else if(scan>=84) key_index=scan-84;
  else if(scan>=72) key_index=scan-72;
  else if(scan>=60) key_index=scan-60;
  else if(scan>=48) key_index=scan-48;
  else if(scan>=36) key_index=scan-36;
  else if(scan>=24) key_index=scan-24;
  else if(scan>=12) key_index=scan-12;
  else key_index=scan;
  selected_octave=(touch[key_index] && !previous_touch[key_index])?octave:key_octave[key_index];
  case(selected_octave)
   0:octave_step=note_step(key_index)>>1;
   2:octave_step=note_step(key_index)<<1;
   default:octave_step=note_step(key_index);
  endcase
  preset=sent[scan]?voice_timbre[scan]:timbre;
  harmonic=(scan<12)?1:(scan<24)?2:(scan<36)?3:(scan<48)?4:
   (scan<60)?5:(scan<72)?6:(scan<84)?7:(scan<96)?8:
   (scan<108)?9:(scan<120)?10:11;
  spectral_gain=spectrum(PURE?2'd3:preset,harmonic);
  // Continuous expression: 31.25% at rest, ~81% at half pressure, 100% full.
  // One shared small multiplier; no additional per-voice state or audio stage.
  pressure_tail=pressure[11:4]-8'd128;
  pressure_tail_scaled={2'b0,pressure_tail}+({2'b0,pressure_tail}<<1);
  if(pressure[11:4]==255) pressure_scale=9'd256;
  else if(!pressure[11]) pressure_scale=9'd80+{1'b0,pressure[11:4]};
  else pressure_scale=9'd208+pressure_tail_scaled[9:3];
  expressive_scale=pressure_scale;
  if(harmonic!=1) expressive_scale=pressure_scale+{2'b0,pressure[11:5]};
  if(expressive_scale>382) expressive_scale=382;
  if(!pressure_enable) expressive_scale=256;
  pressure_product=spectral_gain*expressive_scale;
  layer_gain=pressure_product[15:8];

 end
 always @(posedge clk) begin
  if(rst) begin
   valid<=0;op<=0;voice<=0;step<=0;wave<=0;gain<=0;
   attack<=1024;decay<=128;sustain<=49152;release_rate<=128;
   armed<=0;arm_count<=0;sent<=0;scan<=0;state<=0;alternate<=0;
   desired<=0;base<=0;ratio_r<=65536;product<=0;
   for(k=0;k<128;k=k+1) voice_timbre[k]<=0;
  end else if(!armed) begin
   valid<=0;
   if(mode!=2 && touch!=0) arm_count<=0;
   else if(arm_count>=ARM_WAIT-1) armed<=1;
   else arm_count<=arm_count+1;
  end else case(state)
   0:begin
    desired<=(mode==2)?1'b1:touch[key_index];
    if(mode==2) begin base<=(32'd64+scan*32'd19)<<18;ratio_r<=65536;end
    else begin
     base<=(scan<12)?octave_step:(scan<24)?(octave_step<<1):(scan<36)?((octave_step<<1)+octave_step):(scan<48)?(octave_step<<2):(scan<60)?((octave_step<<2)+octave_step):(scan<72)?((octave_step<<2)+(octave_step<<1)):(scan<84)?((octave_step<<3)-octave_step):(scan<96)?(octave_step<<3):(scan<108)?((octave_step<<3)+octave_step):(scan<120)?((octave_step<<3)+(octave_step<<1)):((octave_step<<3)+(octave_step<<1)+octave_step);
     ratio_r<=ratio;
    end
    state<=1;
   end
   1:begin product<=base*ratio_r;state<=2;end
   2:begin
    voice<=scan;step<=product[47:16];valid<=1;
    if(sent[scan]!=desired) op<=desired?0:1;
    // Roots also need PARAMS updates while a key is held; no retrigger.
    // Update when expression is disabled too, restoring the neutral gain.
    else op<=(alternate && mode!=2)?3:2;
    // 128 * (32/256) / 16 <= 1: retain headroom even at coherent full envelopes.
    if(mode==2) begin wave<=0;gain<=32;attack<=2048;decay<=128;sustain<=50000;release_rate<=256;end
    else begin
     // Limit upper-partial energy before mixing; no post-mix nonlinear shaper.
     if(scan>=12 && product[47:16]>=32'd715827883) gain<=0; // >=8kHz
     else if(scan>=12 && product[47:16]>=32'd447392427) gain<=layer_gain>>1; // >=5kHz
     else gain<=layer_gain;
     case(PURE?0:preset)
      1:begin wave<=0;attack<=2048;decay<=(scan<12)?8:((scan<36)?24:48);sustain<=0;release_rate<=192;end
      2:begin wave<=0;attack<=1024;decay<=96;sustain<=56000;release_rate<=160;end
      default:begin wave<=0;attack<=1024;decay<=32;sustain<=49152;release_rate<=128;end
     endcase
    end
    state<=3;
   end
   3:if(cmd_ready) begin
    valid<=0;sent[scan]<=desired;
    if(op==0) voice_timbre[scan]<=timbre;
    if(scan==127) begin scan<=0;alternate<=!alternate;end else scan<=scan+1'b1;
    state<=0;
   end
   default:begin state<=0;valid<=0;end
  endcase
 end
endmodule
