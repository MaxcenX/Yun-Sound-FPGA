`timescale 1ns/1ps
module tb_effects;
reg clk=0,rst=1,iv=0;always #10 clk=~clk;
reg signed [15:0] dry=0;reg [1:0] mode=0;wire signed [15:0] wet;wire valid;
audio_effects dut(clk,rst,iv,dry,mode,wet,valid);
integer n,count,got,echoes,changed;real early,late;
task put;input integer x;begin
 @(negedge clk);dry=x;iv=1;@(negedge clk);iv=0;count=0;
 while(!valid)begin @(negedge clk);count=count+1;if(count>12)$fatal(1,"FX missed deadline");end
 got=$signed(wet);if(count!=9)$fatal(1,"FX unexpected latency %d",count);
 @(negedge clk);
end endtask
task reset_mode;input [1:0] m;begin
 rst=1;repeat(4)@(negedge clk);rst=0;mode=m;
 for(n=0;n<8200;n=n+1)put(0);
end endtask
initial begin
 reset_mode(0);put(12345);if(got!=12345)$fatal(1,"bypass");put(-12345);if(got!=-12345)$fatal(1,"negative bypass");
 reset_mode(1);echoes=0;
 for(n=0;n<8200;n=n+1)begin put(n==0?12000:0);
 if(n==0 && got!=12000)$fatal(1,"dry onset");
 if(n==4096 && got!=6000)$fatal(1,"echo delay/amplitude %d",got);
 if(n!=0 && n!=4096 && got!=0)$fatal(1,"spurious echo");end
 $display("PASS delay impulse at 4096 samples, half amplitude, exact bypass");
 reset_mode(2);changed=0;
 for(n=0;n<10000;n=n+1)begin put($rtoi(4000*$sin(6.283185307*n/97.0)));
 if(got>4001 || got< -4001)$fatal(1,"chorus gain overflow");if(n>2000 && got!=$signed(dry))changed=changed+1;end
 if(changed<1000)$fatal(1,"chorus not active");
 $display("PASS fractional chorus bounded, modulated output differs from dry");
 reset_mode(3);early=0;late=0;echoes=0;
 for(n=0;n<24000;n=n+1)begin put(n==0?12000:0);
 if(n==0 && got!=12000)$fatal(1,"reverb onset");
 if(n==1091 || n==1597 || n==2131 || n==3253)if(got!=375)$fatal(1,"reverb first taps %d %d",n,got);
 if(n>0 && got!=0)echoes=echoes+1;
 if(n>=1000 && n<6000)early=early+got*got;
 if(n>=19000)late=late+got*got;
 if(got==32767 || got==-32768)$fatal(1,"reverb clips");end
 if(echoes<20 || late>=early)$fatal(1,"reverb decay %f %f",early,late);
 $display("PASS reverb four taps/feedback decay: early_energy=%f late_energy=%f",early,late);
 mode=0;put(-10000);if(got!=-10000)$fatal(1,"effect switch bypass stale tail");
 $display("PASS all effects, 9-clock output latency");$finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
