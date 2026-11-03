`timescale 1ns/1ps
// K selects independent FSR DO trigger; DO is low when pressed.
module gate_control #(parameter DEBOUNCE=50000)(input wire clk,rst,k_n,fsr_n,
 output reg gated,output reg pressed);
 reg [1:0] ks,fs;reg kval,fval,kreleased;
 integer kc,fc,release_count;
 always @(posedge clk) begin
  if(rst) begin ks<=3;fs<=3;kval<=1;fval<=1;kreleased<=0;kc<=0;fc<=0;release_count<=0;gated<=0;pressed<=0;end
  else begin
   ks<={ks[0],k_n};fs<={fs[0],fsr_n};
   if(ks[1]) begin
    if(release_count>=DEBOUNCE+2) kreleased<=1;
    else release_count<=release_count+1;
   end else release_count<=0;
   if(ks[1]==kval) begin kc<=0;end
   else if(kc>=DEBOUNCE-1) begin
    kval<=ks[1];kc<=0;
    if(!ks[1] && kreleased) begin gated<=!gated;kreleased<=0;end
   end else kc<=kc+1;
   if(fs[1]==fval) fc<=0;
   else if(fc>=DEBOUNCE-1) begin fval<=fs[1];pressed<=!fs[1];fc<=0;end
   else fc<=fc+1;
  end
 end
endmodule
