module ads_instrument(input wire clk_50m,input wire [2:0] key_n,input wire joy_k_n,inout wire touch_scl,touch_sda,aud_i2c_scl,aud_i2c_sda,output wire i2s_mclk,input wire i2s_bclk,i2s_daclrc,output wire i2s_dacdat,led_ready,led_touch,seg_dio,seg_sclk,seg_rclk,bt_tx,inout wire adc_scl,adc_sda,input wire bt_rx,output wire led_sdi,led_sck,led_lat);
wire debug_gate;
ads_core #(.TEST_ONLY(0),.DIAGNOSTIC(0)) core(clk_50m,key_n,joy_k_n,touch_scl,touch_sda,aud_i2c_scl,aud_i2c_sda,i2s_mclk,i2s_bclk,i2s_daclrc,i2s_dacdat,led_ready,led_touch,seg_dio,seg_sclk,seg_rclk,debug_gate,adc_scl,adc_sda,bt_rx,bt_tx,led_sdi,led_sck,led_lat);
endmodule
