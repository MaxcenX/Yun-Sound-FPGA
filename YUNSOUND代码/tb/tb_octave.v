`timescale 1ns/1ps
module tb_octave;
reg clk=0,rst=1,k_n=0;always #10 clk=~clk;
wire [1:0] octave;reg [11:0] touch=0;reg [1:0] mode=0;
reg [16:0] ratio=65536;
wire valid,armed;wire [1:0] op,wave;wire [4:0] voice;wire [31:0] step;
wire [7:0] gain;wire [15:0] a,d,s,r;
reg [31:0] steps[0:31];integer i;
display_page #(.DEFAULT_PAGE(1),.DEBOUNCE(5)) button(clk,rst,k_n,octave);
performance_control #(.ARM_WAIT(5)) control(clk,rst,touch,mode,2'd0,ratio,1'b1,12'd0,1'b1,valid,op,voice,step,wave,gain,a,d,s,r,armed,octave);
always @(posedge clk) if(valid && (op==0 || op==2)) steps[voice]<=step;
task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
task press;begin k_n=0;cycles(20);k_n=1;cycles(20);end endtask
task settle;begin cycles(1000);end endtask
initial begin
for(i=0;i<32;i=i+1)steps[i]=0;
cycles(5);rst=0;cycles(30);if(octave!=1)$fatal(1,"held startup");
k_n=1;cycles(20);k_n=0;cycles(2);k_n=1;cycles(20);if(octave!=1)$fatal(1,"bounce");
touch=1;settle;if(steps[0]!=23409859)$fatal(1,"C4");
k_n=0;cycles(100);if(octave!=2)$fatal(1,"hold repeated");k_n=1;cycles(20);
touch=3;settle;if(steps[0]!=23409859 || steps[1]!=49603764)$fatal(1,"held/new octave");
if(steps[13]!=99207528 || steps[25]!=148811292)$fatal(1,"layers same octave");
touch=2;settle;press;settle;
if(octave!=0 || steps[0]!=23409859)$fatal(1,"release tail pitch");
touch=3;settle;if(steps[0]!=11704929 || steps[1]!=49603764)$fatal(1,"low/new vs held high");
ratio=98304;settle;if(steps[0]!=17557393 || steps[1]!=74405646)$fatal(1,"bend with stored octave");
press;if(octave!=1)$fatal(1,"wrap");
mode=2;settle;for(i=0;i<32;i=i+1)if(steps[i]!=((64+19*i)<<18))$fatal(1,"spectrum invariance");
$display("PASS K: debounce, held boot, no repeats, 4->5->3->4; per-key octave hold/release tail, 2f/3f layers, expression, fixed spectrum");$finish;
end
endmodule

