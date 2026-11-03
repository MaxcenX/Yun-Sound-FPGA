create_clock -name clk_50m -period 20.000 [get_ports {clk_50m}]
# BCLK/LRCLK are sampled asynchronously by synchronizer pipelines.
# Bound board-level data response separately in the bring-up report.
set_output_delay -clock clk_50m -max 10.000 [get_ports {i2s_dacdat}]
set_output_delay -clock clk_50m -min 0.000 [get_ports {i2s_dacdat}]
