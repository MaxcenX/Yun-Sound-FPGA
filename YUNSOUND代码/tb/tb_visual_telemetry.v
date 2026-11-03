`timescale 1ns/1ps
module tb_visual_telemetry;
reg clk=0,rst=1,valid=0;always #10 clk=~clk;
reg signed [15:0] wet=0,dry=0;wire [1023:0] wave,xy;wire [255:0] bands;
wire [7:0] meta;
visual_telemetry dut(clk,rst,valid,wet,dry,wave,bands,xy,8'd2,meta);
integer n;integer amp;
integer qi,original,decoded,shiftbits;
 always @(posedge clk)if(!rst && dut.packing && dut.pack_phase==2 && dut.pack_index==127)begin
 #1;shiftbits=8-meta[7:4];
 for(qi=0;qi<128;qi=qi+1)begin
 original=$signed(dut.raw_wave[qi]);decoded=$signed(wave[(127-qi)*8+:8]);decoded=decoded<<<shiftbits;
 if(original-decoded<0 || original-decoded>=(1<<shiftbits))$fatal(1,"wave quantization/order %d %d %d",qi,original,decoded);
 end
 end
task tone;input integer amplitude;begin
 for(n=0;n<512;n=n+1)begin @(negedge clk);wet=$rtoi(amplitude*$sin(6.28318530718*12*n/512));dry=wet;valid=1;@(negedge clk);valid=0;repeat(1040)@(negedge clk);end
 repeat(1040)@(negedge clk);
end endtask
initial begin repeat(5)@(negedge clk);rst=0;tone(10000);
 if(bands[87:80]<65||bands[87:80]>90)$fatal(1,"bin12 amplitude %d",bands[87:80]);
 if(bands[79:72]>3||bands[95:88]>3)$fatal(1,"neighbor leakage");
 if(wave==0||xy==0)$fatal(1,"no capture");
 tone(240);if(meta[7:4]<7 || wave==0)$fatal(1,"weak signal block scale");
 tone(2500);if(bands[87:80]<15||bands[87:80]>23)$fatal(1,"linearity");
 tone(0);if(bands!==0)$fatal(1,"silence");tone(0);tone(0);tone(0);if(wave!==0||xy!==0)$fatal(1,"stale silence wave");
 $display("PASS 512-sample 32-bin DFT amplitude/linearity/silence, 128-point wave and 64-pair XY");$finish;end
endmodule
