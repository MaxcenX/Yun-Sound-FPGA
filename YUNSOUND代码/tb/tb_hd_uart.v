`timescale 1ns/1ps
module tb_hd_uart;
reg clk=0,rst=1;always #10 clk=~clk;
wire tx;wire [7:0] out;wire ov;reg [7:0] idx=2;
reg [1023:0] w={128{8'h11}};wire [255:0] b={32{8'h22}};wire [1023:0] xy={128{8'h33}};
score_status_tx #(.CLK_HZ(960000)) dut(clk,rst,1'b0,8'd0,8'd1,idx,8'd14,8'd60,8'd4,8'd0,8'd0,8'd0,tx,8'd0,8'd0,12'd0,8'd7,w,b,xy,2'd0,8'd2,8'h52);
uart_rx #(.CLK_HZ(960000)) monitor(clk,rst,tx,out,ov);
integer clocks=0,pos=0,size=0,chunks=0,seen=0,t0=0;reg [7:0] check=0,ft=0,pidx=0,seq=0;
always @(posedge clk)begin clocks=clocks+1;if(ov)begin
 if(pos==0)begin if(out!=8'ha5)$fatal(1,"header");pos=1;end
 else if(pos==1)begin ft=out;size=out==8'h5d ?24:out==8'h5e ?11:out==8'h5b ?16:0;if(size==0)$fatal(1,"type");check=0;pos=2;end
 else if(pos==size-1)begin if(out!==check)$fatal(1,"xor");if(ft==8'h5d)chunks=chunks+1;else seen=pidx;pos=0;end
 else begin check=check^out;
 if(ft!=8'h5d&&pos==3)pidx=out;
 if(ft==8'h5d)begin
 if(pos==2&&out!=4)$fatal(1,"version");if(pos==6&&out!=8'h52)$fatal(1,"scale metadata");if(pos==4)seq=out;
 if(pos==5 && seq==1 && out!=chunks)$fatal(1,"chunk order");
 if(pos>=7 && pos<=22 && seq==1 && out!=8'h11)$fatal(1,"snapshot changed");
 end
 pos=pos+1;
 end
 end end
initial begin repeat(5)@(negedge clk);rst=0;wait(seen==2);repeat(1000)@(negedge clk);idx=3;t0=clocks;wait(seen==3);if(clocks-t0>15000)$fatal(1,"idle event latency");$display("idle fast status %d cycles /960000Hz",clocks-t0);
 wait(dut.active && dut.frame_end==23);idx=4;t0=clocks;w=0;wait(seen==4);if(clocks-t0>36000)$fatal(1,"blocked status latency");$display("event during chunk %d cycles /960000Hz",clocks-t0);
 wait(chunks==8);$display("PASS 8 atomic HD chunks with fast-event interleaving, payload/checksum/snapshot consistency");$finish;end
initial begin #100000000;$fatal(1,"timeout");end
endmodule

