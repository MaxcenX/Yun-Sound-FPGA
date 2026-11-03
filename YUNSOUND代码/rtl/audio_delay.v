`timescale 1ns/1ps

// One 4096-sample feed-forward echo (85.33 ms at 48 kHz).
// The memory is deliberately not reset: fill_count suppresses unread history.
// Disabling the effect bypasses the mix, while history continues recording.
// Each input sample produces valid/wet one clock later, including in bypass.
module audio_delay (
    input wire clk,
    input wire rst,
    input wire sample_valid,
    input wire signed [15:0] dry,
    input wire enable,
    output reg signed [15:0] wet,
    output reg valid
);
    reg signed [15:0] history [0:4095];
    reg [11:0] write_addr;
    reg [12:0] fill_count;
    reg signed [15:0] delayed_sample;
    reg signed [15:0] dry_pipe;
    reg enable_pipe;
    reg history_ready_pipe;
    reg valid_pipe;

    wire signed [17:0] dry_wide = {{2{dry_pipe[15]}}, dry_pipe};
    wire signed [17:0] delayed_wide =
        {{2{delayed_sample[15]}}, delayed_sample};
    wire signed [17:0] mixed = dry_wide +
        ((enable_pipe && history_ready_pipe) ?
         (delayed_wide >>> 1) : 18'sd0);

    // Synchronous read-before-write RAM. Keep the RAM and read register out
    // of the reset branch so synthesis can infer embedded block memory.
    always @(posedge clk) begin
        if (!rst && sample_valid) begin
            delayed_sample <= history[write_addr];
            history[write_addr] <= dry;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            write_addr <= 12'd0;
            fill_count <= 13'd0;
            dry_pipe <= 16'sd0;
            enable_pipe <= 1'b0;
            history_ready_pipe <= 1'b0;
            valid_pipe <= 1'b0;
            wet <= 16'sd0;
            valid <= 1'b0;
        end else begin
            valid_pipe <= sample_valid;
            valid <= valid_pipe;

            if (sample_valid) begin
                dry_pipe <= dry;
                enable_pipe <= enable;
                history_ready_pipe <= (fill_count == 13'd4096);
                write_addr <= write_addr + 1'b1;
                if (fill_count != 13'd4096)
                    fill_count <= fill_count + 1'b1;
            end

            if (valid_pipe) begin
                if (mixed > 18'sd32767)
                    wet <= 16'sd32767;
                else if (mixed < -18'sd32768)
                    wet <= -16'sd32768;
                else
                    wet <= mixed[15:0];
            end
        end
    end
endmodule
