`timescale 1ns/1ps
module tb_score_ble;
 reg clk=0,rst=1,rx=1,tick=0;always #10 clk=~clk;
 reg [11:0] touch=0;reg [1:0] oct=1;
 wire tx,override_mode,correct,beat,done,downloaded,error;
 wire [1:0] mode;wire [3:0] target,goal_oct;wire [5:0] cursor;wire [6:0] length;
 score_ble #(.CLK_HZ(960000),.BEAT_SCALE(1200),.FLASH_SAMPLES(2)) dut(
 clk,rst,rx,mode!=0,tick,touch,oct,tx,override_mode,mode,target,goal_oct,correct,beat,done,cursor,length,downloaded,error,1024'd0,256'd0,1024'd0,8'he0,8'd19,12'd2457,8'd7,,,,,8'd2);
 wire [7:0] out;wire ov;
 uart_rx #(.CLK_HZ(960000)) monitor(clk,rst,tx,out,ov);
 integer ack_count=0,frames=0,fp=0;reg [7:0] last_ack,checksum;reg [7:0] frame[0:23];integer fsize=16;
 always @(posedge clk) if(ov) begin
  if(fp==0 && out==8'ha5) begin fp=1;checksum=0;end
  else if(fp!=0) begin
   frame[fp]=out;
   if(fp==1)begin if(out==8'h5b)fsize=16;else if(out==8'h5e)fsize=11;else if(out==8'h5d)fsize=24;else $fatal(1,"header");end
   if(fp>=2 && fp<fsize-1)checksum=checksum^out;
   if(fp==fsize-1) begin if(out!=checksum)$fatal(1,"status XOR");if(fsize==16 && (frame[10]!=8'he0 || frame[11]!=19 || frame[12]!=8'h99 || frame[13]!=9 || frame[14]!=7))$fatal(1,"expression payload");frames=frames+1;fp=0;end
   else fp=fp+1;
  end else begin last_ack=out;ack_count=ack_count+1;end
 end
 task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
 task byte_send;input [7:0] b;integer j;begin
  rx=0;cycles(100);for(j=0;j<8;j=j+1)begin rx=b[j];cycles(100);end rx=1;cycles(100);
 end endtask
 task command;input [1023:0] s;input [7:0] expected;integer j,old,n;begin
  old=ack_count;for(j=127;j>=0;j=j-1)if(s[j*8+:8]!=0)byte_send(s[j*8+:8]);
  n=0;while(ack_count==old && n<120000)begin cycles(1);n=n+1;end
  if(ack_count==old || last_ack!=expected)$fatal(1,"command %s reply %h expected %h",s,last_ack,expected);
 end endtask
 task samples;input integer n;integer j;begin
  for(j=0;j<n;j=j+1)begin tick=1;cycles(1);tick=0;cycles(1);end
 end endtask
 initial begin
 cycles(5);rst=0;cycles(10);command("?;","0");
 command("B0278;","B");command("W003C0100;","E");command("C;","E");
 if(downloaded)$fatal(1,"partial upload became active");
 command("W003C013D;","K");command("W003C013D;","K");
 command("W02400143;","E");command("W01400142;","K");command("C;","C");
 if(!downloaded || length!=2 || mode!=0)$fatal(1,"commit");
 command("P;","P");cycles(20);
 oct=2;touch=1;cycles(20);if(correct)$fatal(1,"wrong octave accepted");
 oct=1;cycles(10);if(correct)$fatal(1,"held key changed its onset octave");
 touch=0;cycles(20);touch=1;cycles(20);if(!correct)$fatal(1,"correct note target=%d oct=%d stored=%d midi=%d mode=%d cursor=%d done=%b",target,goal_oct,dut.onset_octave[0],dut.midi,mode,cursor,done);
 cycles(100);if(cursor!=0)$fatal(1,"advanced before release");touch=0;cycles(20);
 if(cursor!=1 || target!=4 || goal_oct!=4)$fatal(1,"next note");
 touch=16;cycles(20);touch=0;cycles(20);if(!done)$fatal(1,"completion");
 command("B0178;","B");command("W003D013E;","K");command("B0Z78;","E");
 if(length!=2)$fatal(1,"staging changed active length");
 command("R;","R");cycles(10);samples(9);if(cursor!=0)$fatal(1,"tempo early");
 samples(1);if(cursor!=1)$fatal(1,"tempo one beat");samples(10);if(!done)$fatal(1,"rhythm completion");
 command("C;","C");if(length!=1)$fatal(1,"second bank");
 command("B0178;","B");command("W00000101;","K");command("C;","C");command("P;","P");
 if(target!=15)$fatal(1,"rest");samples(10);if(!done)$fatal(1,"rest duration");
 command("01234567890;","E");byte_send("B");cycles(960010);command(";","E");
 command("D;","D");if(downloaded || length!=14)$fatal(1,"builtin restore");
 command("L0091;","L");if(!dut.remote_led_valid || dut.remote_led_mask!=12'h091)$fatal(1,"chord LED");
 command("L1000;","E");if(dut.remote_led_mask!=12'h091)$fatal(1,"invalid LED mutated");
 command("LFFFF;","L");if(dut.remote_led_valid)$fatal(1,"LED release");
 command("L0001;","L");force dut.led_lease=0;cycles(2);release dut.led_lease;cycles(2);if(dut.remote_led_valid)$fatal(1,"LED timeout");
 command("L0002;","L");command("S;","S");if(dut.remote_led_valid)$fatal(1,"stop LED");
 command("V1;","V");if(dut.graph_select!=1)$fatal(1,"view select");command("T4;","T");if(dut.graph_stride!=4)$fatal(1,"stride");
 command("N;","N");touch=0;cycles(20);touch=1;cycles(20);if(cursor!=1)$fatal(1,"press did not advance");cycles(100);if(cursor!=1)$fatal(1,"held repeated");touch=0;cycles(20);touch=1;cycles(20);if(cursor!=2)$fatal(1,"repress failed");touch=0;
 cycles(120000);if(frames<1)$fatal(1,"no telemetry");
 rst=1;cycles(5);rst=0;cycles(20);if(downloaded || mode!=0)$fatal(1,"RAM reset behavior");
 $display("PASS real UART framing, TX replies/status XOR, checked sequential dual-bank upload, retry, partial/error isolation, octave-aware follow/release/done, rhythm/rest timing, timeout, builtin and reset");$finish;
 end
 initial begin #1000000000;$fatal(1,"timeout");end
endmodule


