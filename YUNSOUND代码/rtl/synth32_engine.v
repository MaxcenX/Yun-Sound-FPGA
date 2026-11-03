`timescale 1ns/1ps
// 128 independent DDS/ADSR voices, rendered by one shared arithmetic pipeline.
// No CPU, recorded PCM, or audio stream. waveform.v is a mathematical cycle LUT.
//
// Command handshake: hold cmd_valid and all data until cmd_ready is high at a
// rising clk edge. Commands are stalled during a render and on sample_tick,
// giving every voice a coherent snapshot of the parameter bank. An accepted
// NOTE_ON remains pending until a sample, even if NOTE_OFF follows before it.
// Multiple accepted NOTE_ONs for the same voice before a sample coalesce into
// one restart with the most recent parameters (there can only be one such voice).
//
// sample_valid pulses 768 clk cycles after an accepted sample_tick. At 50 MHz
// this is 15.36 us, below the 20.833 us period at 48 kHz. Feed the output into the
// NEXT I2S frame; sample_tick must precede the output latch by this interval.
module synth32_engine #(
 parameter integer MIX_SHIFT = 4
)(
 input wire clk, rst, sample_tick,
 input wire cmd_valid,
 input wire [1:0] cmd_op,
 input wire [6:0] cmd_voice,
 input wire [31:0] cmd_step,
 input wire [1:0] cmd_wave,
 input wire [7:0] cmd_gain,
 input wire [15:0] cmd_attack, cmd_decay, cmd_sustain, cmd_release,
 output wire cmd_ready,
 output reg signed [15:0] sample,
 output reg sample_valid,
 output reg [127:0] active,
 output reg overrun
);
 localparam NOTE_ON=2'd0, NOTE_OFF=2'd1, PITCH=2'd2, PARAMS=2'd3;
 localparam IDLE=3'd0, ATTACK=3'd1, DECAY=3'd2,
            SUSTAIN=3'd3, RELEASE=3'd4;

 reg [31:0] phase[0:127], step[0:127];
 reg [15:0] env[0:127], attack[0:127], decay[0:127], sustain[0:127], rel[0:127];
 reg [2:0] state[0:127];
 reg [1:0] wave_mode[0:127];
 reg [7:0] gain[0:127];
 reg [127:0] gate, pending, frame_pending, frame_active;
 reg busy;
 reg [6:0] voice_index;
 reg [2:0] stage;
 assign cmd_ready = !rst && !busy && !sample_tick;

 integer c;
 always @(posedge clk) begin
  if(rst) begin
   gate<=0; pending<=0;
   for(c=0;c<128;c=c+1) begin
    step[c]<=0; wave_mode[c]<=0; gain[c]<=0;
    attack[c]<=2048; decay[c]<=256; sustain[c]<=49152; rel[c]<=256;
   end
  end else begin
   if(sample_tick && !busy) pending<=0;
   if(cmd_valid && cmd_ready) case(cmd_op)
    NOTE_ON: begin
     gate[cmd_voice]<=1; pending[cmd_voice]<=1;
     step[cmd_voice]<=cmd_step; wave_mode[cmd_voice]<=cmd_wave; gain[cmd_voice]<=cmd_gain;
     attack[cmd_voice]<=(cmd_attack==0)?16'd1:cmd_attack;
     decay[cmd_voice]<=(cmd_decay==0)?16'd1:cmd_decay;
     sustain[cmd_voice]<=cmd_sustain;
     rel[cmd_voice]<=(cmd_release==0)?16'd1:cmd_release;
    end
    NOTE_OFF: gate[cmd_voice]<=0; // retain a not-yet-rendered NOTE_ON
    PITCH: step[cmd_voice]<=cmd_step; // phase/envelope remain continuous
    PARAMS: begin
     wave_mode[cmd_voice]<=cmd_wave;
     // Smooth expression in the existing parameter bank. Avoid a second
     // 128x8 register/mux bank; NOTE_ON still relies on its ADSR attack.
     if(cmd_gain>gain[cmd_voice]) gain[cmd_voice]<=
       (cmd_gain-gain[cmd_voice]>2)?gain[cmd_voice]+8'd2:cmd_gain;
     else if(gain[cmd_voice]>cmd_gain) gain[cmd_voice]<=
       (gain[cmd_voice]-cmd_gain>2)?gain[cmd_voice]-8'd2:cmd_gain;
     attack[cmd_voice]<=(cmd_attack==0)?16'd1:cmd_attack;
     decay[cmd_voice]<=(cmd_decay==0)?16'd1:cmd_decay;
     sustain[cmd_voice]<=cmd_sustain;
     rel[cmd_voice]<=(cmd_release==0)?16'd1:cmd_release;
    end
   endcase
  end
 end

 // Shared registers isolate the 128:1 state selectors from the arithmetic.
 reg [31:0] phase_r, step_r, render_phase;
 reg [15:0] env_r, attack_r, decay_r, sustain_r, release_r, render_env;
 reg [2:0] state_r;
 reg [1:0] mode_r;
 reg [7:0] gain_r;
 wire [7:0] gain_smooth[0:127]; // read-only diagnostic alias
 genvar gi;
 generate for(gi=0;gi<128;gi=gi+1) begin: gain_alias
  assign gain_smooth[gi]=gain[gi];
 end endgenerate
 reg gate_r, trigger_r;
 wire signed [15:0] raw_wave;
 waveform shared_waveform(.phase(render_phase), .mode(mode_r), .value(raw_wave));
 reg signed [15:0] wave_r;
 reg signed [32:0] env_product;
 reg signed [24:0] gain_product;
 wire signed [15:0] env_scaled = $signed(env_product[31:16]);
 wire signed [15:0] voice_scaled = $signed(gain_product[23:8]);
 reg signed [21:0] sum;
 reg signed [21:0] mix_next, master;
 reg [15:0] next_env;
 reg [2:0] next_state;
 reg [16:0] add_env;
 integer i;
 always @(posedge clk) begin
  if(rst) begin
   sample<=0; sample_valid<=0; active<=0; overrun<=0;
   busy<=0; stage<=0; voice_index<=0; frame_pending<=0; frame_active<=0;
   phase_r<=0; step_r<=0; render_phase<=0;
   env_r<=0; attack_r<=0; decay_r<=0; sustain_r<=0; release_r<=0; render_env<=0;
   state_r<=IDLE; mode_r<=0; gain_r<=0; gate_r<=0; trigger_r<=0;
   wave_r<=0; env_product<=0; gain_product<=0; sum<=0;
   for(i=0;i<128;i=i+1) begin phase[i]<=0; env[i]<=0; state[i]<=IDLE; end
  end else begin
   sample_valid<=0;
   if(sample_tick && busy) overrun<=1; // sticky diagnostic; never restart mid-frame
   if(sample_tick && !busy) begin
    busy<=1; stage<=0; voice_index<=0; sum<=0;
    frame_pending<=pending; frame_active<=0;
   end else if(busy) case(stage)
    0: begin
     phase_r<=phase[voice_index]; step_r<=step[voice_index];
     env_r<=env[voice_index]; state_r<=state[voice_index];
     attack_r<=attack[voice_index]; decay_r<=decay[voice_index];
     sustain_r<=sustain[voice_index]; release_r<=rel[voice_index];
     mode_r<=wave_mode[voice_index];
     gain_r<=gain[voice_index];
     gate_r<=gate[voice_index]; trigger_r<=frame_pending[voice_index];
     stage<=1;
    end
    1: begin
     next_env=env_r; next_state=state_r; add_env=0;
     if(trigger_r) begin
      // One attack increment is rendered even for an on/off event between frames.
      next_env=attack_r;
      next_state=(attack_r==16'hffff)?DECAY:ATTACK;
     end else if(!gate_r) begin
      if(env_r<=release_r) begin next_env=0; next_state=IDLE; end
      else begin next_env=env_r-release_r; next_state=RELEASE; end
     end else case(state_r)
      ATTACK: begin
       add_env={1'b0,env_r}+{1'b0,attack_r};
       if(add_env>=17'd65535) begin next_env=65535; next_state=DECAY; end
       else next_env=add_env[15:0];
      end
      DECAY: begin
       if(env_r<=sustain_r || (env_r-sustain_r)<=decay_r) begin
        next_env=sustain_r; next_state=SUSTAIN;
       end else next_env=env_r-decay_r;
      end
      SUSTAIN: next_env=sustain_r;
      default: begin next_env=attack_r; next_state=ATTACK; end
     endcase
     env[voice_index]<=next_env; state[voice_index]<=next_state;
     // Sample the phase after one increment. Restart is explicit only on NOTE_ON.
     render_phase<=trigger_r?step_r:phase_r+step_r;
     phase[voice_index]<=trigger_r?step_r:phase_r+step_r;
     render_env<=next_env;
     frame_active[voice_index]<=gate_r || next_env!=0;
     stage<=2;
    end
    2: begin wave_r<=raw_wave; stage<=3; end
    3: begin
     env_product<=$signed(wave_r)*$signed({1'b0,render_env});
     stage<=4;
    end
    4: begin
     gain_product<=$signed(env_scaled)*$signed({1'b0,gain_r});
     stage<=5;
    end
    5: begin
     mix_next=sum+$signed({{6{voice_scaled[15]}},voice_scaled});
     if(voice_index==127) begin
      master=mix_next >>> MIX_SHIFT;
      if(master>32767) sample<=16'sh7fff;
      else if(master< -32768) sample<=16'sh8000;
      else sample<=master[15:0];
      sample_valid<=1; active<=frame_active; busy<=0;
     end else begin
      sum<=mix_next; voice_index<=voice_index+1'b1; stage<=0;
     end
    end
    default: begin busy<=0; overrun<=1; end
   endcase
  end
 end
endmodule
