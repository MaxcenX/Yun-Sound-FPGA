`timescale 1ns/1ps
module tb_visual_uart;
reg clk=0,rst=1;always #10 clk=~clk;
reg [7:0] idx=2;
wire tx;wire [7:0] rx;wire valid;
localparam [191:0] W={24{8'h11}};
localparam [63:0] B={8{8'h22}};
localparam [255:0] XY={32{8'h33}};
score_status_tx #(.CLK_HZ(960000),.BAUD(9600)) dut(clk,rst,1'b0,8'd0,
 8'd1,idx,8'd14,8'd67,8'd4,8'd1,8'd0,8'd0,
 tx,8'd0,8'd0,12'd0,8'd7,W,B,XY);
uart_rx #(.CLK_HZ(960000),.BAUD(9600)) mon(clk,rst,tx,rx,valid);
integer pos=0,status_count=0,graphic_count=0,cycles=0;
integer clock_count=0,changed_at=0,latency=0;reg [7:0] seen_index=0,pending_index=0;
always @(posedge clk) clock_count=clock_count+1;
reg visual=0;reg [7:0] parity=0;
always @(posedge clk) if(valid) begin
 if(pos==0) begin if(rx!==8'hA5)$fatal(1,"header %h",rx);pos=1;end
 else if(pos==1) begin
  if(rx!==8'h5B && rx!==8'h5C)$fatal(1,"type %h",rx);
  visual=(rx==8'h5C);parity=0;pos=2;
 end else begin
  if(pos<(visual?67:15)) begin
   parity=parity^rx;if(!visual && pos==3)pending_index=rx;
   if(visual && pos>=3 && pos<27 && rx!==8'h11)$fatal(1,"wave byte");
   if(visual && pos>=27 && pos<35 && rx!==8'h22)$fatal(1,"band byte");
   if(visual && pos>=35 && pos<67 && rx!==8'h33)$fatal(1,"xy byte");
   pos=pos+1;
  end else begin
   if(rx!==parity)$fatal(1,"checksum %h %h",rx,parity);
   if(visual)graphic_count=graphic_count+1;else begin status_count=status_count+1;seen_index=pending_index;end
   pos=0;
  end
 end
end
initial begin
 repeat(5)@(negedge clk);rst=0;
 wait(status_count>=1);
 repeat(1000)@(negedge clk);idx=3;changed_at=clock_count;
 while(seen_index!=3 && clock_count-changed_at<96000)@(negedge clk);
 latency=clock_count-changed_at;if(seen_index!=3||latency>24000)$fatal(1,"idle event delayed %d cycles",latency);
 $display("idle event UART completion %d cycles at 960000Hz",latency);
 wait(dut.visual_frame && dut.frame_active);idx=4;changed_at=clock_count;
 while(seen_index!=4 && clock_count-changed_at<105600)@(negedge clk);
 latency=clock_count-changed_at;if(seen_index!=4||latency>105600)$fatal(1,"graphics blocked event %d",latency);
 $display("event during graphics UART completion %d cycles at 960000Hz",latency);
 if(graphic_count<1)$fatal(1,"missing graphics");
 $display("PASS FPGA graphics UART: 68-byte frame, 24 wave, 8 bands, 16 XY, XOR and legacy status");$finish;
end
endmodule
