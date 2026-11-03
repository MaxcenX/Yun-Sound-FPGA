`timescale 1ns/1ps
module tb_reader_latency;
reg clk=0,rst=1;always #10 clk=~clk;
tri1 scl,sda;reg [15:0] keys=0;wire [11:0] touch;wire ready,fault;wire [6:0] addr;
mpr121_reader #(.POWER_WAIT(10),.RESET_WAIT(10),.SETTLE_WAIT(10)) dut(clk,rst,scl,sda,touch,ready,fault,addr);
mpr121_model model(scl,sda,1'b1,7'h5a,keys);
realtime t0;integer fh;
initial begin
 fh=$fopen("instrument128_fx/sim/reader_latency.csv","w");$fdisplay(fh,"case,register_to_touch_us");
 repeat(5)@(negedge clk);rst=0;wait(ready);
 // Change just AFTER byte0 has been latched by the independent slave.
 wait(dut.state==13 && model.ptr==0 && model.state==4 && model.bits==0 && dut.polls==1);
 #1;t0=$realtime;keys=1;wait(touch==1);
 $fdisplay(fh,"normal_missed_byte,%0.3f",($realtime-t0)/1000);
 keys=0;wait(touch==0);
 wait(dut.state==13 && model.ptr==0 && model.state==4 && model.bits==0 && dut.polls==127);
 #1;t0=$realtime;keys=1;wait(touch==1);
 $fdisplay(fh,"health_check_missed_byte,%0.3f",($realtime-t0)/1000);
 if(fault)$fatal(1,"Fault");$fclose(fh);$display("PASS reader boundary including periodic config readback");$finish;
end
initial begin #400000000;$fatal(1,"Timeout");end
endmodule
