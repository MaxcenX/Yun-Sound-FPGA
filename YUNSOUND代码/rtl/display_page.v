`timescale 1ns/1ps
module display_page #(parameter DEFAULT_PAGE=1,DEBOUNCE=500000)(
 input wire clk,rst,k_n,output reg [1:0] page);
 reg [1:0] sync;reg candidate,armed;integer count,warm;
 always @(posedge clk) begin
  if(rst) begin sync<=3;candidate<=1;armed<=0;count<=0;warm<=0;page<=DEFAULT_PAGE;end
  else begin
   sync<={sync[0],k_n};
   if(warm<3) warm<=warm+1;
   else if(sync[1]!=candidate) begin candidate<=sync[1];count<=0;end
   else if(count<DEBOUNCE-1) count<=count+1;
   else if(candidate) armed<=1;
   else if(armed) begin page<=(page==2)?0:page+1'b1;armed<=0;end
  end
 end
endmodule
