`timescale 1ns/1ps
// Sample-domain delay, fractional chorus and four-tap feedback reverberator.
// One read port, one write port; 10 clocks/sample, no CPU or prerecorded audio.
module audio_effects(input wire clk,rst,valid_in,input wire signed [15:0] dry,
 input wire [1:0] mode,output reg signed [15:0] wet,output reg valid);
reg signed [15:0] history[0:8191];
reg [12:0] wr,rd;reg [13:0] fill;
reg signed [15:0] q,d,t0,t1,t2,t3;
reg [3:0] state;reg [1:0] selected,last_mode;
reg [31:0] lfo;wire [15:0] triangle=lfo[31]?~lfo[30:15]:lfo[30:15];
reg [7:0] fraction;reg [12:0] chorus_delay;reg usable;
wire signed [19:0] sum=$signed(t0)+$signed({{4{t1[15]}},t1})+$signed({{4{t2[15]}},t2})+$signed({{4{t3[15]}},t3});
wire signed [16:0] delta=$signed({t1[15],t1})-$signed({t0[15],t0});
wire signed [25:0] fraction_product=delta*$signed({1'b0,fraction});
wire signed [26:0] interpolated=$signed(t0)+(fraction_product>>>8);
wire signed [27:0] out_mix=!usable||selected==0?d:selected==1?($signed(d)+($signed(t0)>>>1)):
 selected==2?(($signed(d)*3+interpolated)>>>2):($signed(d)+(sum>>>3));
wire signed [23:0] feedback=selected==3 && usable?(($signed(d)>>>2)+((sum*3)>>>4)):d;
function signed [15:0] sat; input signed [27:0] x;begin
 if(x>32767)sat=32767;else if(x< -32768)sat=-32768;else sat=x[15:0];end endfunction
always @(posedge clk) begin
 q<=history[rd];
 if(!rst && state==9)history[wr]<=sat(feedback);
end
always @(posedge clk)begin
 if(rst)begin wr<=0;rd<=0;fill<=0;state<=0;selected<=0;last_mode<=0;lfo<=0;
 d<=0;t0<=0;t1<=0;t2<=0;t3<=0;fraction<=0;chorus_delay<=640;usable<=0;wet<=0;valid<=0;end
 else begin
 valid<=0;
 case(state)
 0:if(valid_in)begin
 d<=dry;selected<=mode;last_mode<=mode;usable<=fill==8192 && mode==last_mode;
 if(mode!=last_mode)fill<=0;
 fraction<=triangle[7:0];chorus_delay<=13'd640+{5'd0,triangle[15:8]};lfo<=lfo+32'd89478;
 rd<=wr-((mode==1)?13'd4096:(mode==2)?(13'd640+{5'd0,triangle[15:8]}):13'd1091);state<=1;end
 1:state<=2;
 2:begin t0<=q;rd<=wr-((selected==2)?chorus_delay+13'd1:13'd1597);state<=3;end
 3:state<=4;
 4:begin t1<=q;rd<=wr-13'd2131;state<=5;end
 5:state<=6;
 6:begin t2<=q;rd<=wr-13'd3253;state<=7;end
 7:state<=8;
 8:begin t3<=q;state<=9;end
 9:begin wet<=sat(out_mix);valid<=1;wr<=wr+1'b1;if(fill<8192)fill<=fill+1'b1;state<=0;end
 default:state<=0;
 endcase
 end
end
endmodule
