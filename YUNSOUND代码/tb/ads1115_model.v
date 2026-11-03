`timescale 1ns/1ps
// Behavioral I2C slave, independent of DUT states. Checks read ACK/NACK order.
module ads1115_model(input wire scl,inout wire sda,input wire connected,
 input wire [6:0] address,input wire [15:0] x,y,p,
 input wire stuck_conversion,corrupt_config);
 reg low=0;
 assign sda=low?1'b0:1'bz;
 reg [15:0] config_reg=16'h8583,conversion=0,snapshot=0;
 reg [7:0] high_write;integer write_byte=0,conversions=0;
 reg conversion_busy=0;realtime finish_at=0;
 parameter CONVERSION_NS=1188000;
 integer state=8,bits=0,j,starts=0,stops=0,reads=0,writes=0;
 reg [7:0] rx=0,tx=0,ptr=0;
 reg expect_addr=1,expect_reg=0,selected=0,reading=0,ack_ok=0;
 integer read_bytes=0;
 localparam RX=0,ASET=1,ACLK=2,AEND=3,TX=4,TEND=5,MACK=6,TSTART=7,WAITING=8;
 function [15:0] word_at;
 input [7:0] a;
 begin
  if(a==1) word_at=((config_reg & 16'h7fff) | ((!stuck_conversion && $realtime>=finish_at)?16'h8000:16'h0000)) ^ (corrupt_config?16'h0200:16'h0000);
  else word_at=conversion;
 end endfunction
 function [7:0] data_at;
 input integer index;
 begin data_at=index==0?snapshot[15:8]:snapshot[7:0];end
 endfunction
 always @(negedge sda) if(scl===1'b1) begin
  state=RX;bits=0;rx=0;expect_addr=1;reading=0;selected=0;starts=starts+1;read_bytes=0;
 end
 always @(posedge sda) if(scl===1'b1) begin state=WAITING;low=0;stops=stops+1;end
 always @(posedge scl) begin
  case(state)
   RX:begin
    rx={rx[6:0],sda};
    if(bits==7) begin
     bits=0;
     if(expect_addr) begin
      selected=connected && rx[7:1]==address;
      reading=rx[0];ack_ok=selected;expect_addr=0;expect_reg=!reading;
     end else begin
      ack_ok=selected && connected;
      if(ack_ok) begin
       if(expect_reg) begin ptr=rx;expect_reg=0;write_byte=0;end
       else begin
        if(write_byte==0) high_write=rx;
        else if(write_byte==1 && ptr==1) begin
         config_reg={high_write,rx};
         if(config_reg[15]) begin
          if(config_reg[14:12]<4 || config_reg[14:12]>6 || config_reg[11:0]!=12'h3e3)
           $fatal(1,"ADS unexpected config %h",config_reg);
          if(config_reg[14:12]==4) conversion=x;
          else if(config_reg[14:12]==5) conversion=y;
          else conversion=p;
          finish_at=$realtime+CONVERSION_NS;conversions=conversions+1;
         end
        end
        write_byte=write_byte+1;writes=writes+1;
       end
      end
     end
     state=ASET;
    end else bits=bits+1;
   end
   ACLK:state=AEND;
   TX:if(bits==7) state=TEND;else bits=bits+1;
   MACK:begin
    read_bytes=read_bytes+1;reads=reads+1;
    if(read_bytes==1 && sda!==0) $fatal(1,"first read byte missing master ACK");
    if(read_bytes==2 && sda!==1) $fatal(1,"last read byte missing master NACK");
    if(sda) state=WAITING;
    else begin tx=data_at(read_bytes);bits=0;state=TSTART;end
   end
  endcase
 end
 always @(negedge scl) begin
  case(state)
   ASET:begin low=ack_ok;state=ACLK;end
   AEND:begin
    low=0;
    if(!ack_ok) state=WAITING;
    else if(reading) begin snapshot=word_at(ptr);tx=data_at(0);bits=0;low=~tx[7];state=TX;end
    else begin rx=0;bits=0;state=RX;end
   end
   TX:low=~tx[7-bits];
   TEND:begin low=0;state=MACK;end
   TSTART:begin low=~tx[7];state=TX;end
  endcase
 end
endmodule
