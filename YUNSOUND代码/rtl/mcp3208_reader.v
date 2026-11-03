// Three single-ended channels for MCP3208 (also CH0..CH2 of MCP3204).
// Mode 0: change MOSI on falling edges; sample MISO on rising edges.
// 50 MHz / (2 * 200) = 125 kHz SPI, 192 us per 24-bit transaction.
// Three channels fit inside the default 1 ms scan period.
// ready means a full SPI scan completed. This ADC has no ACK or identity
// register, so ready MUST NOT be interpreted as proof of a connected chip.
module mcp3208_reader #(
    parameter integer HALF_CYCLES = 200,
    parameter integer SCAN_CYCLES = 50000,
    parameter integer STARTUP_CYCLES = 2500000
) (
    input wire clk,
    input wire rst,
    input wire miso,
    output reg cs_n,
    output reg sclk,
    output reg mosi,
    output reg [11:0] x,
    output reg [11:0] y,
    output reg [11:0] pressure,
    output reg valid,
    output reg ready
);
    localparam [1:0] STARTUP = 2'd0, IDLE = 2'd1,
                     TRANSFER = 2'd2, GAP = 2'd3;
    localparam integer HALF_LIMIT = (HALF_CYCLES > 0) ? HALF_CYCLES : 1;
    localparam integer SCAN_LIMIT = (SCAN_CYCLES > 0) ? SCAN_CYCLES : 1;
    localparam integer STARTUP_LIMIT = (STARTUP_CYCLES > 0) ? STARTUP_CYCLES : 1;
    reg [1:0] state, channel;
    reg [31:0] startup_count, scan_count, half_count;
    reg [4:0] bit_index;
    reg [23:0] tx_shift;
    reg [11:0] rx_shift, pending_x, pending_y;
    reg first_scan;
    // At 125 kHz the ADC output is stable for about 4 us before the
    // sampling edge. Synchronization adds only 40 ns at 50 MHz.
    reg miso_meta, miso_sync;
    always @(posedge clk) begin
        if (rst) begin
            miso_meta <= 1'b0;
            miso_sync <= 1'b0;
        end else begin
            miso_meta <= miso;
            miso_sync <= miso_meta;
        end
    end

    function [23:0] command;
        input [1:0] selected_channel;
        begin
            // Bytes: {0x06 | (CH >> 2), (CH & 3) << 6, 0x00}.
            // This reader intentionally scans only channels 0, 1 and 2.
            command = 24'h060000 | ({22'd0, selected_channel} << 14);
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state <= STARTUP;
            channel <= 0;
            startup_count <= 0;
            scan_count <= 0;
            half_count <= 0;
            bit_index <= 23;
            tx_shift <= 0;
            rx_shift <= 0;
            pending_x <= 0;
            pending_y <= 0;
            first_scan <= 1'b1;
            cs_n <= 1'b1;
            sclk <= 1'b0;
            mosi <= 1'b0;
            x <= 0;
            y <= 0;
            pressure <= 0;
            valid <= 1'b0;
            ready <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (state != STARTUP && scan_count < SCAN_LIMIT - 1)
                scan_count <= scan_count + 1'b1;
            case (state)
                STARTUP: begin
                    if (startup_count >= STARTUP_LIMIT - 1) begin
                        startup_count <= 0;
                        state <= IDLE;
                    end else startup_count <= startup_count + 1'b1;
                end
                IDLE: begin
                    if (first_scan || scan_count >= SCAN_LIMIT - 1) begin
                        first_scan <= 1'b0;
                        scan_count <= 0;
                        channel <= 0;
                        tx_shift <= command(0);
                        rx_shift <= 0;
                        bit_index <= 23;
                        half_count <= 0;
                        cs_n <= 1'b0;
                        sclk <= 1'b0;
                        mosi <= 1'b0; // command bit 23 is zero
                        state <= TRANSFER;
                    end
                end
                TRANSFER: begin
                    if (half_count >= HALF_LIMIT - 1) begin
                        half_count <= 0;
                        if (!sclk) begin
                            sclk <= 1'b1;
                            rx_shift <= {rx_shift[10:0], miso_sync};
                        end else begin
                            sclk <= 1'b0;
                            if (bit_index == 0) begin
                                cs_n <= 1'b1;
                                mosi <= 1'b0;
                                if (channel == 0) begin
                                    pending_x <= rx_shift;
                                    channel <= 1;
                                    state <= GAP;
                                end else if (channel == 1) begin
                                    pending_y <= rx_shift;
                                    channel <= 2;
                                    state <= GAP;
                                end else begin
                                    // Publish a coherent triplet, never a
                                    // mixture of old and new channel scans.
                                    x <= pending_x;
                                    y <= pending_y;
                                    pressure <= rx_shift;
                                    valid <= 1'b1;
                                    ready <= 1'b1;
                                    state <= IDLE;
                                end
                            end else begin
                                bit_index <= bit_index - 1'b1;
                                tx_shift <= {tx_shift[22:0], 1'b0};
                                mosi <= tx_shift[22];
                            end
                        end
                    end else half_count <= half_count + 1'b1;
                end
                GAP: begin
                    // CS high for one half period (4 us by default),
                    // exceeding the data-sheet 500 ns minimum.
                    if (half_count >= HALF_LIMIT - 1) begin
                        half_count <= 0;
                        tx_shift <= command(channel);
                        rx_shift <= 0;
                        bit_index <= 23;
                        cs_n <= 1'b0;
                        sclk <= 1'b0;
                        mosi <= 1'b0;
                        state <= TRANSFER;
                    end else half_count <= half_count + 1'b1;
                end
                default: begin
                    state <= STARTUP;
                    startup_count <= 0;
                    first_scan <= 1'b1;
                    cs_n <= 1'b1;
                    sclk <= 1'b0;
                    mosi <= 1'b0;
                    ready <= 1'b0;
                end
            endcase
        end
    end
endmodule
