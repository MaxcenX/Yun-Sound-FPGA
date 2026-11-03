`timescale 1ns/1ps
module tb_pressure_expression;
reg clk=0,rst=1;always #10 clk=~clk;
reg [11:0] touch=0,pressure=0;
reg [1:0] mode=0,timbre=0;
reg enable=1;
wire valid,armed;wire [1:0] op,wave;wire [6:0] voice;
wire [31:0] step;wire [7:0] gain;wire [15:0] attack,decay,sustain,rel;
performance_control #(.ARM_WAIT(1)) dut(clk,rst,touch,mode,timbre,17'd65536,enable,pressure,1'b1,valid,op,voice,step,wave,gain,attack,decay,sustain,rel,armed,2'd1);
integer p,t,i,noteons,params,previous[0:127],current[0:127],rest_root,full_root;
reg [127:0] seen;
always @(posedge clk) if(!rst && valid)begin
 if(op==0)noteons=noteons+1;
 if(op==3)params=params+1;
 if(op==0 || op==3)begin current[voice]=gain;seen[voice]=1;end
end
task sweep;
begin
 seen=0;repeat(1100)@(negedge clk);
 if(seen!=={128{1'b1}})$fatal(1,"missing continuous gain update");
end endtask
initial begin
 for(t=0;t<4;t=t+1)begin
 rst=1;touch=0;pressure=0;mode=0;timbre=t;enable=1;noteons=0;params=0;
 repeat(5)@(negedge clk);rst=0;wait(armed);@(negedge clk);touch=12'hfff;
 sweep;rest_root=current[0];
 if(rest_root<40 || rest_root>70)$fatal(1,"rest not approx 31 percent");
 for(i=0;i<128;i=i+1)previous[i]=current[i];
 // Entire 8-bit control curve, including both piecewise boundaries.
 for(p=1;p<256;p=p+1)begin
 pressure=p*16;sweep;
 for(i=0;i<128;i=i+1)begin
 if(current[i]<previous[i])$fatal(1,"nonmonotonic gain");
 previous[i]=current[i];
 end
 if(p==128 && current[0]<rest_root*2)$fatal(1,"weak mid pressure");
 end
 full_root=current[0];
 if(full_root<3*rest_root)$fatal(1,"insufficient dynamic range");
 if(noteons!=128)$fatal(1,"expression retriggered notes");
 pressure=0;sweep;
 if(current[0]!=rest_root)$fatal(1,"release pressure did not return");
 enable=0;sweep;
 if(current[0]!=full_root)$fatal(1,"disable did not restore root");
 if(t==3 && current[12]!=0)$fatal(1,"sine acquired harmonics");
 $display("PASS tone=%0d root rest=%0d full=%0d monotonic curve, held-key PARAMS without retrigger",t,rest_root,full_root);
 end
 rst=1;touch=0;mode=2;enable=1;pressure=0;noteons=0;
 repeat(5)@(negedge clk);rst=0;wait(armed);sweep;
 for(i=0;i<128;i=i+1)if(current[i]!=32)$fatal(1,"testmode gain changed");
 $display("PASS 128-frequency test mode independent of pressure");
 $finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
