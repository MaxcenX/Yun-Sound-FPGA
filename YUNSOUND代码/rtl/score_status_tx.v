`timescale 1ns/1ps
module score_status_tx #(parameter CLK_HZ=50000000,BAUD=9600)(
 input wire clk,rst,reply_valid,input wire [7:0] reply,
 input wire [7:0] mode,index,length,midi,octave,touch_l,touch_h,flags,
 output wire tx,input wire [7:0] expression_bend,expression_depth,
 input wire [11:0] expression_pressure,input wire [7:0] expression_flags,
 input wire [1023:0] visual_wave,input wire [255:0] visual_bands,input wire [1023:0] visual_xy,
 input wire [1:0] graph_select,input wire [7:0] graph_stride,input wire [7:0] wave_meta);
 reg [7:0] fifo[0:15];reg [3:0] wp,rp;reg [4:0] count;
 reg [31:0] timer,gtimer;reg pending,gpending;reg [63:0] last_state;
 wire [63:0] live={flags,touch_h,touch_l,octave,midi,length,index,mode};
 wire event_pending=(live!=last_state);
 reg active,start;reg [4:0] pos,frame_end;reg [191:0] frame;reg [7:0] data;wire busy;
 reg graph_active;reg [1:0] kind;reg [7:0] seq,chunk,saved_stride;reg [1023:0] snapshot;
 wire [127:0] payload=snapshot[127:0];
 function [7:0] xor128;input [127:0] p;integer j;begin xor128=0;for(j=0;j<16;j=j+1)xor128=xor128^p[j*8+:8];end endfunction
 wire [7:0] gcheck=8'd4^{6'd0,kind}^seq^chunk^saved_stride^xor128(payload);
 wire [7:0] basic_check=mode^index^length^midi^octave^touch_l^touch_h^flags;
 wire [7:0] full_check=basic_check^expression_bend^expression_depth^expression_pressure[7:0]^{4'd0,expression_pressure[11:8]}^expression_flags;
 wire push=reply_valid && count<16;
 wire pop=!busy&&!start&&!active&&count!=0;
 uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) uart(clk,rst,start,data,tx,busy);
 always @(posedge clk) if(rst)begin
 wp<=0;rp<=0;count<=0;timer<=0;gtimer<=0;pending<=0;gpending<=0;last_state<=0;
 active<=0;start<=0;pos<=0;frame_end<=0;frame<=0;data<=0;graph_active<=0;kind<=0;seq<=0;chunk<=0;saved_stride<=2;snapshot<=0;
 end else begin
 start<=0;
 if(push)begin fifo[wp]<=reply;wp<=wp+1'b1;end
 if(pop)rp<=rp+1'b1;
 case({push,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:begin end endcase
 if(timer>=CLK_HZ/10-1)begin timer<=0;pending<=1;end else timer<=timer+1'b1;
 if(gtimer>=CLK_HZ/3-1)begin gtimer<=0;gpending<=1;end else gtimer<=gtimer+1'b1;
 if(!busy&&!start)begin
 if(active)begin data<=frame[7:0];frame<=frame>>8;start<=1;if(pos==frame_end)active<=0;else pos<=pos+1'b1;end
 else if(count!=0)begin data<=fifo[rp];start<=1;end
 else if(event_pending)begin
 frame<={basic_check,live,8'h5e,8'ha5};pos<=0;frame_end<=10;active<=1;last_state<=live;
 end else if(pending)begin
 frame<={full_check,expression_flags,4'd0,expression_pressure[11:8],expression_pressure[7:0],expression_depth,expression_bend,live,8'h5b,8'ha5};
 pos<=0;frame_end<=15;active<=1;pending<=0;timer<=0;last_state<=live;
 end else if(graph_active && graph_select==kind)begin
 frame<={gcheck,payload,saved_stride,chunk,seq,6'd0,kind,8'd4,8'h5d,8'ha5};pos<=0;frame_end<=23;active<=1;
 snapshot<=snapshot>>128;
 if(chunk==(kind==1?1:7))graph_active<=0;else chunk<=chunk+1'b1;
 end else if(graph_active)graph_active<=0;
 else if(gpending && graph_select!=3)begin
 kind<=graph_select;seq<=seq+1'b1;chunk<=0;saved_stride<=(graph_select==0)?wave_meta:graph_stride;graph_active<=1;gpending<=0;
 case(graph_select)0:snapshot<=visual_wave;1:snapshot<={768'd0,visual_bands};default:snapshot<=visual_xy;endcase
 end
 end
 end
endmodule
