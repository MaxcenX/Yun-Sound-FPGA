`timescale 1ns/1ps
// Three independent single-ended channels, ADDR=GND -> 0x48.
// PGA +/-4.096V (125uV/LSB), 860SPS, single-shot. Poll OS then read data.
// One shared ADC, sequential conversions; publish only complete XYZ groups.
module ads1115_reader #(parameter I2C_Q=125, POWER_WAIT=2500000,
 CONVERT_WAIT=60000, RETRY_WAIT=5000000, MAX_POLLS=16)(
 input wire clk,rst,inout wire scl,sda,
 output reg [15:0] x,y,p,output reg valid,ready,fault,
 output reg [3:0] fault_code);
 reg start,rd;reg [7:0] reg_addr;reg [15:0] wr_data;
 wire busy,done;wire [1:0] error;wire [15:0] result;
 i2c_word16 #(.Q(I2C_Q)) bus(clk,rst,start,rd,7'h48,reg_addr,wr_data,scl,sda,busy,done,error,result);
 reg [3:0] state;reg [1:0] channel;integer timer,polls;
 reg [15:0] hold_x,hold_y;
 wire [15:0] config_word=16'hc3e3+({14'd0,channel}<<12);
 task fail;
 input [3:0] code;
 begin ready<=0;fault<=1;fault_code<=code;timer<=0;state<=9;channel<=0;end
 endtask
 always @(posedge clk) begin
  if(rst) begin
   start<=0;rd<=0;reg_addr<=0;wr_data<=0;x<=0;y<=0;p<=0;
   hold_x<=0;hold_y<=0;valid<=0;ready<=0;fault<=0;fault_code<=0;
   state<=0;channel<=0;timer<=0;polls<=0;
  end else begin
   start<=0;valid<=0;
   if(done && error!=0) fail(error==1?4'd1:4'd2);
   else case(state)
    0:if(timer>=POWER_WAIT-1) begin timer<=0;state<=1;end else timer<=timer+1;
    1:if(!busy) begin rd<=0;reg_addr<=1;wr_data<=config_word;start<=1;state<=2;end
    2:if(done) begin timer<=0;polls<=0;state<=3;end
    3:if(timer>=CONVERT_WAIT-1) begin timer<=0;state<=4;end else timer<=timer+1;
    4:if(!busy) begin rd<=1;reg_addr<=1;start<=1;state<=5;end
    5:if(done) begin
     if(result[14:0]!=config_word[14:0]) fail(4'd3);
     else if(result[15]) state<=6;
     else if(polls>=MAX_POLLS-1) fail(4'd4);
     else begin polls<=polls+1;state<=4;end
    end
    6:if(!busy) begin rd<=1;reg_addr<=0;start<=1;state<=7;end
    7:if(done) begin
     // Small negative codes from single-ended offset are clamped to zero.
     if(channel==0) hold_x<=result[15]?16'd0:result;
     if(channel==1) hold_y<=result[15]?16'd0:result;
     if(channel==2) begin
      x<=hold_x;y<=hold_y;p<=result[15]?16'd0:result;
      valid<=1;ready<=1;fault<=0;fault_code<=0;channel<=0;
     end else channel<=channel+1'b1;
     state<=1;
    end
    9:if(timer>=RETRY_WAIT-1) begin timer<=0;state<=1;end else timer<=timer+1;
    default:state<=0;
   endcase
  end
 end
endmodule
