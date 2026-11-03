set_device -name GW5A-25A GW5A-LV25UG324C2/I1
add_file -type verilog rtl/adc_reader.v
add_file -type verilog rtl/ads1115_reader.v
add_file -type verilog rtl/ads_axis.v
add_file -type verilog rtl/ads_core.v
add_file -type verilog rtl/led595_driver.v
add_file -type verilog rtl/visual_telemetry.v
add_file -type verilog rtl/ads_pressure_map.v
add_file -type verilog rtl/audio_effects.v
add_file -type verilog rtl/codec_master_init.v
add_file -type verilog rtl/display_page.v
add_file -type verilog rtl/expression_ratio.v
add_file -type verilog rtl/external_axis.v
add_file -type verilog rtl/gate_control.v
add_file -type verilog rtl/i2c_reg16.v
add_file -type verilog rtl/i2c_word16.v
add_file -type verilog rtl/i2c_write24.v
add_file -type verilog rtl/i2s_codec_master.v
add_file -type verilog rtl/joystick_control.v
add_file -type verilog rtl/lesson_guide.v
add_file -type verilog rtl/mcp3208_reader.v
add_file -type verilog rtl/mpr121_reader.v
add_file -type verilog rtl/performance_control.v
add_file -type verilog rtl/performance_ui.v
add_file -type verilog rtl/pitch_lut.v
add_file -type verilog rtl/seg_display.v
add_file -type verilog rtl/synth32_engine.v
add_file -type verilog rtl/waveform.v
add_file -type verilog rtl/ads_instrument.v
add_file -type cst constraints/ads.cst
add_file -type sdc constraints/audio.sdc
set_option -top_module ads_instrument
set_option -verilog_std v2001
add_file -type verilog rtl/uart_rx.v
add_file -type verilog rtl/uart_tx.v
add_file -type verilog rtl/score_ble.v
add_file -type verilog rtl/score_status_tx.v
run all


