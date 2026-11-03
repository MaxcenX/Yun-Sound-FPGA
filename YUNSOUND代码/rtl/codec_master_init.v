`timescale 1ns/1ps
// 50MHz controller. WM8960 audio MASTER, 12.5MHz MCLK reference.
// PLL N=7, K=0xDD4413, /4 fixed, /2 SYSCLK => 12.288MHz nominal.
// Speaker/ADC disabled; headphone 0dB; DAC unmute only after clocks_ok.
module codec_master_init #(
 parameter POWER_WAIT=1000000, WRITE_WAIT=100000, LONG_WAIT=25000000,
 parameter CLOCK_TIMEOUT=5000000
)(input wire clk,rst,clocks_ok,inout wire scl,sda,
 output reg done,error,output reg [5:0] failed_index,
 output wire [1:0] bus_error);
 reg start;
 wire busy,transfer_done;
 reg [5:0] index;
 reg [2:0] state;
 integer count,limit;
 function [15:0] cfg;
 input [5:0] n;
 begin case(n)
  0:cfg={7'd15,9'h000};
  1:cfg={7'd5, 9'h008}; // mute
  2:cfg={7'd25,9'h1c0}; // charge VMID
  3:cfg={7'd25,9'h0c0}; // normal VMID
  4:cfg={7'd52,9'h027}; // fractional, no prescale, N=7
  5:cfg={7'd53,9'h0dd};
  6:cfg={7'd54,9'h044};
  7:cfg={7'd55,9'h013};
  8:cfg={7'd26,9'h001}; // PLL power, wait 500ms
  9:cfg={7'd4, 9'h005}; // PLL source, SYSCLK /2
 10:cfg={7'd8, 9'h1c4}; // BCLK=SYSCLK/4; class D disabled
 11:cfg={7'd7, 9'h042}; // master, I2S, 16-bit
 12:cfg={7'd47,9'h00c}; // DAC output mixers
 13:cfg={7'd34,9'h100};
 14:cfg={7'd37,9'h100};
 15:cfg={7'd10,9'h0ff};
 16:cfg={7'd11,9'h1ff};
 17:cfg={7'd2, 9'h079}; // 0dB headphone L, latch (+12dB vs baseline)
 18:cfg={7'd3, 9'h179}; // 0dB headphone R, update both channels
 19:cfg={7'd26,9'h1e1}; // PLL + DACs + headphones; wait500ms
 20:cfg={7'd6, 9'h008}; // soft unmute ramp
 21:cfg={7'd5, 9'h000}; // unmute ONLY after validated clock frames
 default:cfg=0;
 endcase end endfunction
 wire [15:0] word_data=cfg(index);
 i2c_write24 writer(.clk(clk),.rst(rst),.start(start),.data({8'h34,word_data}),
 .scl(scl),.sda(sda),.busy(busy),.done(transfer_done),.error(bus_error));
 always @(posedge clk) begin
  if(rst) begin
   start<=0;index<=0;state<=0;count<=0;limit<=POWER_WAIT;
   done<=0;error<=0;failed_index<=0;
  end else begin
   start<=0;
   case(state)
    0: if(count>=limit-1) begin count<=0;state<=1;end else count<=count+1;
    1: if(index==21 && !clocks_ok) begin
        if(count>=CLOCK_TIMEOUT-1) begin error<=1;failed_index<=21;state<=3;end
        else count<=count+1;
       end else if(!busy) begin start<=1;state<=2;end
    2: if(transfer_done) begin
     if(bus_error!=0) begin error<=1;failed_index<=index;state<=3;end
     else if(index==21) begin done<=1;state<=3;end
     else begin
      index<=index+1'b1;count<=0;state<=0;
      limit<=(index==2 || index==8 || index==19)?LONG_WAIT:WRITE_WAIT;
     end
    end
    default: ;
   endcase
  end
 end
endmodule
