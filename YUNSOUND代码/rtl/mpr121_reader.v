`timescale 1ns/1ps
// MPR121 initialization and polled two-byte touch snapshots; no CPU required.
// Config: 12 electrodes, 12/6 hysteresis, ESI=1ms, SFI=4, no debounce.
module mpr121_reader #(
 parameter POWER_WAIT=2500000, RESET_WAIT=250000, SETTLE_WAIT=25000000,
 parameter POLL_WAIT=2500, RETRY_WAIT=25000000, I2C_Q=63
)(input wire clk,rst,inout wire scl,sda,
 output reg [11:0] touch,output reg ready,fault,output reg [6:0] address);
 reg start,rd;
 reg [7:0] ra,wd;
 wire busy,done;
 wire [1:0] error;
 wire [15:0] value;
 i2c_reg16 #(.Q(I2C_Q)) bus(clk,rst,start,rd,address,ra,wd,scl,sda,busy,done,error,value);
 reg [4:0] state;
 reg [5:0] index;
 reg [6:0] polls;
 integer timer;
 function [7:0] cfg_reg;
 input [5:0] n;
 begin
  if(n==0) cfg_reg=8'h5e;
  else if(n<=11) cfg_reg=8'h2a+n;
  else if(n<=35) cfg_reg=8'h41+(n-12);
  else case(n)
   36:cfg_reg=8'h5b;37:cfg_reg=8'h5c;
   38:cfg_reg=8'h5d;default:cfg_reg=8'h5e;
  endcase
 end endfunction
 function [7:0] cfg_val;
 input [5:0] n;
 begin
  if(n>=12 && n<=35) cfg_val=n[0]?8'd6:8'd12;
  else case(n)
   1,2,5,6:cfg_val=1;
   7:cfg_val=8'hff;8:cfg_val=2;
   37:cfg_val=8'h10;38:cfg_val=8'h20;39:cfg_val=8'h8c;
   default:cfg_val=0;
  endcase
 end endfunction
 always @(posedge clk) begin
  if(rst) begin
   state<=16;timer<=0;index<=0;polls<=0;
   start<=0;rd<=0;ra<=0;wd<=0;touch<=0;ready<=0;fault<=0;address<=7'h5a;
  end else begin
   start<=0;
   // Never publish a partial or failed read. Reinitialize after transport failure.
   if(done && error!=0 && state!=1) begin
    ready<=0;touch<=0;fault<=1;timer<=0;state<=15;
   end else case(state)
    16:if(timer>=POWER_WAIT-1) begin timer<=0;state<=0;end else timer<=timer+1;
    0:if(!busy) begin ra<=8'h80;wd<=8'h63;rd<=0;start<=1;state<=1;end
    1:if(done) begin
     timer<=0;
     if(error==0) state<=2;
     else if(address<7'h5d) begin address<=address+1'b1;state<=0;end
     else begin fault<=1;state<=15;end
    end
    2:if(timer>=RESET_WAIT-1) begin timer<=0;state<=3;end else timer<=timer+1;
    3:if(!busy) begin ra<=8'h5c;rd<=1;start<=1;state<=4;end
    4:if(done) begin
     if(value!=16'h2410) begin fault<=1;timer<=0;state<=15;end
     else begin index<=0;state<=5;end
    end
    5:if(!busy) begin ra<=cfg_reg(index);wd<=cfg_val(index);rd<=0;start<=1;state<=6;end
    6:if(done) begin
     if(index==39) state<=7;
     else begin index<=index+1'b1;state<=5;end
    end
    7:if(!busy) begin ra<=8'h5c;rd<=1;start<=1;state<=8;end
    8:if(done) begin
     if(value!=16'h2010) begin ready<=0;touch<=0;fault<=1;timer<=0;state<=15;end
     else state<=9;
    end
    9:if(!busy) begin ra<=8'h5e;rd<=1;start<=1;state<=10;end
    10:if(done) begin
     timer<=0;
     if(value[7:0]!=8'h8c) begin ready<=0;touch<=0;fault<=1;state<=15;end
     else if(ready) state<=12;
     else state<=11;
    end
    11:if(timer>=SETTLE_WAIT-1) begin timer<=0;polls<=0;state<=12;end else timer<=timer+1;
    12:if(!busy) begin ra<=0;rd<=1;start<=1;state<=13;end
    13:if(done) begin
     timer<=0;
     if(value[15]) begin ready<=0;touch<=0;fault<=1;state<=15;end // OVCF
     else begin touch<=value[11:0];ready<=1;fault<=0;state<=14;end
    end
    14:if(timer>=POLL_WAIT-1) begin
     timer<=0;polls<=polls+1'b1;
     state<=(polls==127)?7:12; // periodic configuration-health readback
    end else timer<=timer+1;
    15:if(timer>=RETRY_WAIT-1) begin
     timer<=0;address<=7'h5a;index<=0;polls<=0;state<=0;
    end else timer<=timer+1;
    default:state<=16;
   endcase
  end
 end
endmodule
