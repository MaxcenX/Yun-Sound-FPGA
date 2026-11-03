`timescale 1ns/1ps
module tb_reader_fastcheck;
reg clk=0,rst=1;always #10 clk=~clk;
tri1 scl,sda;wire [11:0] touch;wire ready,fault;wire [6:0] addr;
mpr121_reader #(.I2C_Q(5),.POWER_WAIT(100),.RESET_WAIT(100),.SETTLE_WAIT(100),.POLL_WAIT(500),.RETRY_WAIT(500)) dut(clk,rst,scl,sda,touch,ready,fault,addr);
mpr121_model model(scl,sda,1'b1,7'h5a,16'd0);
initial begin repeat(5) @(negedge clk);rst=0;wait(ready);$display("PASS reader ready %0t",$time);$finish;end
initial begin repeat(10) begin #100000;$display("TRACE %0t state=%d error=%d ready=%d fault=%d starts=%d",$time,dut.state,dut.error,ready,fault,model.starts);end $fatal(1,"timeout");end
endmodule
