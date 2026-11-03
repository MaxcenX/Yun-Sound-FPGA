`timescale 1ns/1ps
// Single-master, open-drain 3-byte write. clk=50MHz, Q=125 -> <=100kHz.
// start is a one-clock pulse while busy=0. error valid with done and sticky
// until next start: 0=OK, 1=NACK, 2=bus/clock timeout. No automatic retry.
module i2c_write24 #(parameter Q=125, TIMEOUT_Q=4000)(
 input wire clk,rst,start, input wire [23:0] data,
 inout wire scl,sda, output reg busy,done,output reg [1:0] error);
 reg scl_low,sda_low;
 assign scl=scl_low ? 1'b0:1'bz;
 assign sda=sda_low ? 1'b0:1'bz;
 reg [1:0] cs,ds;
 always @(posedge clk) begin
  if(rst) begin cs<=3;ds<=3;end
  else begin cs<={cs[0],scl};ds<={ds[0],sda};end
 end
 localparam IDLE=0,FREE=1,START=2,SETUP=3,RAISE=4,HIGH=5,FALL=6,
            STOP0=7,STOP1=8,STOP2=9,FINISH=10,START_HOLD=11,STOP_HOLD=12;
 reg [3:0] state;
 reg [23:0] shift;
 reg [3:0] bit_index;
 reg [1:0] byte_index;
 integer divider,timeout_count;
 always @(posedge clk) begin
  if(rst) begin
   scl_low<=0;sda_low<=0;busy<=0;done<=0;error<=0;state<=IDLE;
   shift<=0;bit_index<=0;byte_index<=0;divider<=0;timeout_count<=0;
  end else begin
   done<=0;
   if(state==IDLE) begin
    divider<=0;
    if(start) begin
     shift<=data;bit_index<=0;byte_index<=0;error<=0;busy<=1;
     timeout_count<=0;state<=FREE;
    end
   end else if(divider==Q-1) begin
    divider<=0;
    if(timeout_count>=TIMEOUT_Q) begin
     scl_low<=0;sda_low<=0;error<=2;state<=FINISH;
     timeout_count<=0;
    end else case(state)
     FREE: if(cs[1] && ds[1]) begin state<=START;timeout_count<=0;end
           else timeout_count<=timeout_count+1;
     START: begin sda_low<=1;state<=START_HOLD;end
     START_HOLD: state<=SETUP; // START hold >=5us at default Q
     SETUP: begin
      scl_low<=1;sda_low<=(bit_index==8)?1'b0:~shift[23];state<=RAISE;
     end
     RAISE: begin scl_low<=0;state<=HIGH;end
     HIGH: if(cs[1]) begin
      timeout_count<=0;
      if(bit_index==8 && ds[1]) error<=1;
      state<=FALL;
     end else timeout_count<=timeout_count+1;
     FALL: begin
      scl_low<=1;
      if(bit_index==8) begin
       if(error!=0 || byte_index==2) state<=STOP0;
       else begin byte_index<=byte_index+1'b1;bit_index<=0;state<=SETUP;end
      end else begin shift<={shift[22:0],1'b0};bit_index<=bit_index+1'b1;state<=SETUP;end
     end
     STOP0: begin scl_low<=1;sda_low<=1;state<=STOP1;end
     STOP1: begin scl_low<=0;state<=STOP2;end
     STOP2: if(cs[1]) begin state<=STOP_HOLD;end
            else timeout_count<=timeout_count+1;
     STOP_HOLD: begin sda_low<=0;state<=FINISH;end // STOP setup >=5us
     FINISH: begin busy<=0;done<=1;state<=IDLE;end
     default: state<=IDLE;
    endcase
   end else divider<=divider+1;
  end
 end
endmodule
