`timescale 1ns/1ps
// One static external input on bus1. CST selects IOR9 (C17 positive/C18 negative).
// ADC hard macro is intentionally used directly, not replaced with an RTL ADC.
module adc_reader #(parameter START_CYCLES=5000000, TIMEOUT_CYCLES=100000)(
 input wire clk,rst, output reg [13:0] value,output reg valid,ready,fault);
 // ADC uses its documented internal 2.5MHz oscillator, no fabric generated clock.
 reg request;
 wire done;
 wire [13:0] result;
 ADC #(.CLK_SEL(1'b0),.DIV_CTL(2'd0),.BUF_EN(12'b0),
 .CSR_ADC_MODE(1'b1),.CSR_VSEN_CTRL(3'd0),
 .CSR_SAMPLE_CNT_SEL(3'd4),.CSR_RATE_CHANGE_CTRL(3'd4),
 .CSR_FSCAL(10'd653),.CSR_OFFSET(12'd0)) adc_inst(
 .CLK(1'b0),.VSENCTL(3'b001),.ADCMODE(1'b1),.DRSTN(!rst),
 .ADCREQI(request),.ADCRDY(done),.ADCVALUE(result),.ADCEN(!rst),
 .MDRP_CLK(1'b0),.MDRP_WDATA(8'd0),.MDRP_A_INC(1'b0),.MDRP_OPCODE(2'b00),.MDRP_RDATA());
 reg [1:0] ds;
 always @(posedge clk) if(rst) ds<=0;else ds<={ds[0],done};
 reg [2:0] state;
 integer timer;
 always @(posedge clk) begin
  if(rst) begin state<=0;timer<=0;request<=0;value<=0;valid<=0;ready<=0;fault<=0;end
  else begin
   valid<=0;
   case(state)
    0:if(timer>=START_CYCLES-1) begin timer<=0;request<=1;state<=1;end else timer<=timer+1;
    // Keep the asynchronous request high for 2us, observe completion go low.
    1:if(timer>=99) begin timer<=0;request<=0;state<=2;end else timer<=timer+1;
    2:if(!ds[1]) begin timer<=0;state<=3;end
      else if(timer>=TIMEOUT_CYCLES-1) begin fault<=1;ready<=0;state<=0;timer<=0;end
      else timer<=timer+1;
    3:if(ds[1]) begin timer<=0;state<=4;end
      else if(timer>=TIMEOUT_CYCLES-1) begin fault<=1;ready<=0;state<=0;timer<=0;end
      else timer<=timer+1;
    // ADC result remains stable after done; extra 4 system clocks for capture.
    4:if(timer>=3) begin
       value<=result;valid<=1;ready<=1;fault<=0;timer<=0;state<=5;
      end else timer<=timer+1;
    5:if(timer>=24999) begin request<=1;timer<=0;state<=1;end else timer<=timer+1;
    default:begin state<=0;timer<=0;request<=0;end
   endcase
  end
 end
endmodule

