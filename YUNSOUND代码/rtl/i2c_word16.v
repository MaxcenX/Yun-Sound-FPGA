`timescale 1ns/1ps
// Big-endian 16-bit register write/read for ADS1115, repeated START on read.
// Open drain throughout. Read byte0 ACK, byte1 NACK. MSB-first result.
module i2c_word16 #(parameter Q=250, TIMEOUT_Q=2000)(
 input wire clk,rst,start,rd,input wire [6:0] addr,
 input wire [7:0] reg_addr,input wire [15:0] wr_data,
 inout wire scl,sda,output reg busy,done,output reg [1:0] error,
 output reg [15:0] result);
 reg sl,dl;
 assign scl=sl?1'b0:1'bz;
 assign sda=dl?1'b0:1'bz;
 reg [1:0] cs,ds;
 always @(posedge clk) if(rst) begin cs<=3;ds<=3;end
 else begin cs<={cs[0],scl};ds<={ds[0],sda};end
 localparam IDLE=0,FREE=1,START=2,SHOLD=3,SETUP=4,RAISE=5,HIGH=6,FALL=7,
 RSLOW=8,RSRAISE=9,RSHIGH=10,RSSTART=11,RSHOLD=12,
 STOP0=13,STOP1=14,STOP2=15,STOPH=16,FINISH=17;
 reg [4:0] state;
 reg [2:0] stage;
 reg [3:0] bitn;
 reg [7:0] tx,rx,reg_l;
 reg [15:0] wr_l;
 reg [6:0] addr_l;
 reg rd_l;
 integer div,timeout;
 wire receive_byte=(stage==4 || stage==5);
 always @(posedge clk) begin
  if(rst) begin
   sl<=0;dl<=0;busy<=0;done<=0;error<=0;result<=0;
   state<=IDLE;stage<=0;bitn<=0;tx<=0;rx<=0;reg_l<=0;wr_l<=0;
   addr_l<=0;rd_l<=0;div<=0;timeout<=0;
  end else begin
   done<=0;
   if(state==IDLE) begin
    div<=0;
    if(start) begin
     addr_l<=addr;reg_l<=reg_addr;wr_l<=wr_data;rd_l<=rd;
     tx<={addr,1'b0};rx<=0;stage<=0;bitn<=0;result<=0;
     busy<=1;error<=0;timeout<=0;state<=FREE;
    end
   end else if(div==Q-1) begin
    div<=0;
    if(timeout>=TIMEOUT_Q) begin
     sl<=0;dl<=0;error<=2;timeout<=0;state<=FINISH;
    end else case(state)
     FREE: if(cs[1] && ds[1]) begin timeout<=0;state<=START;end
           else timeout<=timeout+1;
     START: begin dl<=1;state<=SHOLD;end
     SHOLD: state<=SETUP;
     SETUP: begin
      sl<=1;
      if(receive_byte) dl<=(bitn==8 && stage==4);
      else dl<=(bitn==8)?1'b0:~tx[7];
      state<=RAISE;
     end
     RAISE: begin sl<=0;state<=HIGH;end
     HIGH: if(cs[1]) begin
      timeout<=0;
      if(receive_byte && bitn<8) rx<={rx[6:0],ds[1]};
      if(!receive_byte && bitn==8 && ds[1]) error<=1;
      state<=FALL;
     end else timeout<=timeout+1;
     FALL: begin
      sl<=1;
      if(bitn<8) begin bitn<=bitn+1'b1;tx<={tx[6:0],1'b0};state<=SETUP;end
      else begin
       bitn<=0;
       if(error!=0) state<=STOP0;
       else case(stage)
        0:begin tx<=reg_l;stage<=1;state<=SETUP;end
        1:if(rd_l) state<=RSLOW;else begin tx<=wr_l[15:8];stage<=2;state<=SETUP;end
        2:begin tx<=wr_l[7:0];stage<=6;state<=SETUP;end
        6:state<=STOP0;
        3:begin rx<=0;stage<=4;state<=SETUP;end
        4:begin result[15:8]<=rx;rx<=0;stage<=5;state<=SETUP;end
        5:begin result[7:0]<=rx;state<=STOP0;end
        default:state<=STOP0;
       endcase
      end
     end
     RSLOW:begin sl<=1;dl<=0;state<=RSRAISE;end
     RSRAISE:begin sl<=0;state<=RSHIGH;end
     RSHIGH:if(cs[1]) begin timeout<=0;state<=RSSTART;end else timeout<=timeout+1;
     RSSTART:begin dl<=1;state<=RSHOLD;end
     RSHOLD:begin tx<={addr_l,1'b1};stage<=3;state<=SETUP;end
     STOP0:begin sl<=1;dl<=1;state<=STOP1;end
     STOP1:begin sl<=0;state<=STOP2;end
     STOP2:if(cs[1]) begin timeout<=0;state<=STOPH;end else timeout<=timeout+1;
     STOPH:begin dl<=0;state<=FINISH;end
     FINISH:begin busy<=0;done<=1;state<=IDLE;end
     default:state<=IDLE;
    endcase
   end else div<=div+1;
  end
 end
endmodule
