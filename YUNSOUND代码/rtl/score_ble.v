`timescale 1ns/1ps
// ASCII semicolon-framed score transactions. Two banks prevent partial uploads
// from replacing the active song. Contains note events only, never PCM audio.
module score_ble #(parameter CLK_HZ=50000000,BAUD=9600,BEAT_SCALE=2880000,FLASH_SAMPLES=4800,LED_LEASE_CYCLES=150000000)(
 input wire clk,rst,rx,enable,sample_tick,input wire [11:0] touch,input wire [1:0] octave,
 output wire tx,output reg override_mode,output reg [1:0] remote_mode,
 output wire [3:0] target,target_octave,output wire correct,beat,
 output reg done,output reg [5:0] cursor,output wire [6:0] song_length,
 output wire downloaded,output reg upload_error,
 input wire [1023:0] visual_wave,input wire [255:0] visual_bands,input wire [1023:0] visual_xy,
 input wire [7:0] expression_bend,expression_depth,
 input wire [11:0] expression_pressure,input wire [7:0] expression_flags,
 output reg [1:0] graph_select,output reg [7:0] graph_stride,
 output reg [11:0] remote_led_mask,output reg remote_led_valid,input wire [7:0] wave_meta);
 reg [31:0] led_lease;
 wire [7:0] byte_in;wire byte_valid;
 uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) receiver(clk,rst,rx,byte_in,byte_valid);
 reg [7:0] reply;reg reply_start;
 // One-character replies. A valid command is at least two characters long,
 // so the 9600-baud reply completes before the next valid command can finish.
 reg [7:0] buf0,buf1,buf2,buf3,buf4,buf5,buf6,buf7,buf8;
 reg [3:0] used;reg overflow;reg [31:0] idle;
 reg [15:0] notes[0:127];reg bank,have_song,loading;
 reg [6:0] length,expected,written;reg [7:0] tempo,pending_tempo;
 reg [7:0] last_note,last_duration;reg restart;
 function [4:0] hx;input [7:0] c;begin
  if(c>="0" && c<="9") hx=c-"0";
  else if(c>="A" && c<="F") hx=c-"A"+10;
  else if(c>="a" && c<="f") hx=c-"a"+10;
  else hx=16;
 end endfunction
 wire [4:0] h1=hx(buf1),h2=hx(buf2),h3=hx(buf3),h4=hx(buf4),h5=hx(buf5),h6=hx(buf6),h7=hx(buf7),h8=hx(buf8);
 wire [7:0] v1={h1[3:0],h2[3:0]},v2={h3[3:0],h4[3:0]},v3={h5[3:0],h6[3:0]},v4={h7[3:0],h8[3:0]};
 wire hex4=!(h1[4]|h2[4]|h3[4]|h4[4]);
 wire hex8=hex4 && !(h5[4]|h6[4]|h7[4]|h8[4]);
 wire [7:0] sum=v1+v2+v3;
 wire note_ok=(v2==0 || (v2>=48 && v2<=83)) && v3>=1 && v3<=16;
 assign song_length=have_song?length:7'd14;
 assign downloaded=have_song;
 function [15:0] builtin;input [5:0] pos;reg [7:0] n;begin
  case(pos) 0,1,13:n=60;2,3,6:n=67;4,5:n=69;7,8:n=65;9,10:n=64;default:n=62;endcase
  builtin={n,((pos==6 || pos==13)?8'd2:8'd1)};
 end endfunction
 wire [15:0] event_word=have_song?notes[{bank,cursor}]:builtin(cursor);
 wire [7:0] midi=event_word[15:8],duration=event_word[7:0];
 wire rest=(midi==0);
 assign target_octave=rest?4'hf:(midi<60?4'd3:(midi<72?4'd4:4'd5));
 assign target=rest?4'hf:(midi<60?midi-48:(midi<72?midi-60:midi-72));
 reg [11:0] previous_touch;reg [1:0] onset_octave[0:11];integer i;
 always @(posedge clk) if(rst) begin
  previous_touch<=0;for(i=0;i<12;i=i+1) onset_octave[i]<=1;
 end else begin
  previous_touch<=touch;
  for(i=0;i<12;i=i+1) if(touch[i]&&!previous_touch[i]) onset_octave[i]<=octave;
 end
 assign correct=enable && !done && !rest && touch==previous_touch && touch==(12'b1<<target) && ({2'b0,onset_octave[target]}+4'd3)==target_octave;
 reg press_advance;reg matched,armed;reg [21:0] phase;reg [15:0] flash;reg [7:0] beat_index;
 wire [22:0] phase_next={1'b0,phase}+tempo;
 assign beat=enable && !done && flash!=0;
 always @(posedge clk) begin
  if(rst || restart || !enable) begin cursor<=0;done<=0;matched<=0;armed<=0;phase<=0;flash<=FLASH_SAMPLES;beat_index<=0;end
  else if(!done) begin
   if(touch==0) armed<=1;
   if(armed && correct) matched<=1;
   if(sample_tick) begin
    if(flash!=0) flash<=flash-1'b1;
    if(phase_next>=BEAT_SCALE) begin
     phase<=phase_next-BEAT_SCALE;flash<=FLASH_SAMPLES;
     if(remote_mode==2 || rest) begin
      if(beat_index+1>=duration) begin
       beat_index<=0;matched<=0;armed<=(touch==0);
       if(cursor+1>=song_length) done<=1;else cursor<=cursor+1'b1;
      end else beat_index<=beat_index+1'b1;
     end
    end else phase<=phase_next[21:0];
   end
   if(remote_mode!=2 && !rest && ((press_advance && armed && correct) || (!press_advance && matched && touch==0))) begin
    matched<=0;armed<=!press_advance;phase<=0;beat_index<=0;flash<=FLASH_SAMPLES;
    if(cursor+1>=song_length) done<=1;else cursor<=cursor+1'b1;
   end
  end
 end
 always @(posedge clk) begin
  if(rst) begin
   remote_led_mask<=0;remote_led_valid<=0;led_lease<=0;graph_select<=0;graph_stride<=2;press_advance<=0;used<=0;overflow<=0;idle<=0;bank<=0;have_song<=0;loading<=0;
   length<=0;expected<=0;written<=0;tempo<=120;pending_tempo<=120;
   last_note<=0;last_duration<=0;restart<=0;override_mode<=0;remote_mode<=0;
   reply<=0;reply_start<=0;upload_error<=0;
   buf0<=0;buf1<=0;buf2<=0;buf3<=0;buf4<=0;buf5<=0;buf6<=0;buf7<=0;buf8<=0;
  end else begin
   restart<=0;reply_start<=0;
   if(led_lease!=0) led_lease<=led_lease-1'b1;else remote_led_valid<=0;
   if(used!=0 || overflow) begin
    if(idle>=CLK_HZ-1) begin used<=0;overflow<=0;idle<=0;upload_error<=1;end
    else idle<=idle+1'b1;
   end
   if(byte_valid) begin
    idle<=0;
    if(byte_in==";") begin
     used<=0;overflow<=0;
     reply<=8'h45;reply_start<=1;upload_error<=1; // E: rejected, no mutation
     if(!overflow) begin
      if(used==5 && buf0=="L" && hex4 && (v1<16 || (v1==255 && v2==255))) begin
       remote_led_mask<={v1[3:0],v2};remote_led_valid<=(v1!=255);led_lease<=(v1!=255)?LED_LEASE_CYCLES:0;reply<="L";upload_error<=0;
      end else if(used==5 && buf0=="B" && hex4 && v1>=1 && v1<=64 && v2>=40 && v2<=240) begin
       loading<=1;expected<=v1;written<=0;pending_tempo<=v2;reply<="B";upload_error<=0;
      end else if(used==9 && buf0=="W" && loading && hex8 && sum==v4 && note_ok) begin
       if(v1==written && written<expected) begin
        notes[{!bank,v1[5:0]}]<={v2,v3};written<=written+1'b1;
        last_note<=v2;last_duration<=v3;reply<="K";upload_error<=0;
       end else if(written!=0 && v1==written-1 && v2==last_note && v3==last_duration) begin reply<="K";upload_error<=0;end
      end else if(used==1 && buf0=="C" && loading && written==expected) begin
       bank<=!bank;have_song<=1;length<=expected;tempo<=pending_tempo;loading<=0;
       remote_mode<=0;override_mode<=1;restart<=1;reply<="C";upload_error<=0;
      end else if(used==1 && (buf0=="P" || buf0=="R" || buf0=="S" || buf0=="N")) begin
       remote_led_valid<=0;led_lease<=0;press_advance<=(buf0=="N");remote_mode<=(buf0=="P"||buf0=="N")?1:(buf0=="R"?2:0);override_mode<=1;restart<=1;
       reply<=buf0;upload_error<=0;
      end else if(used==1 && buf0=="D") begin
       have_song<=0;loading<=0;tempo<=120;override_mode<=1;remote_mode<=0;restart<=1;reply<="D";upload_error<=0;
      end else if(used==2 && buf0=="V" && buf1>="0" && buf1<="3") begin
       graph_select<=buf1-"0";reply<="V";upload_error<=0;
      end else if(used==2 && buf0=="T" && (buf1=="1"||buf1=="2"||buf1=="4"||buf1=="8")) begin
       graph_stride<=buf1-"0";reply<="T";upload_error<=0;
      end else if(used==1 && buf0=="?") begin
       reply<=loading?"U":(have_song?"1":"0");upload_error<=0;
      end
     end
    end else if(byte_in!=13 && byte_in!=10 && byte_in!=32) begin
     case(used)
      0:buf0<=byte_in;1:buf1<=byte_in;2:buf2<=byte_in;3:buf3<=byte_in;
      4:buf4<=byte_in;5:buf5<=byte_in;6:buf6<=byte_in;7:buf7<=byte_in;8:buf8<=byte_in;
      default:overflow<=1;
     endcase
     if(used<10) used<=used+1'b1;else overflow<=1;
    end
   end
  end
 end
 score_status_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) sender(clk,rst,reply_start,reply,
  (enable?(remote_mode==2?8'd2:8'd1):8'd0),{2'b0,cursor},{1'b0,song_length},midi,
  ({6'b0,octave}+8'd3),touch[7:0],{4'b0,touch[11:8]},
  {2'b0,press_advance,loading,upload_error,downloaded,done,correct},tx,
  expression_bend,expression_depth,expression_pressure,expression_flags,
  visual_wave,visual_bands,visual_xy,graph_select,graph_stride,wave_meta);
endmodule



