`timescale 1ns/1ps

// Three independent active-low buttons. A stable release arms each button;
// a stable subsequent press acts once. A button held across reset does not
// act until it has been released and pressed again.
module performance_ui #(
    parameter integer DEBOUNCE_CYCLES = 50000
) (
    input wire clk,
    input wire rst,
    input wire [2:0] key,
    output reg [1:0] timbre,
    output reg [1:0] effect_on,
    output reg [1:0] mode
);
    function integer count_width;
        input integer count;
        integer value;
        begin
            value = count - 1;
            count_width = 0;
            while (value > 0) begin
                count_width = count_width + 1;
                value = value >> 1;
            end
            if (count_width < 1)
                count_width = 1;
        end
    endfunction

    localparam integer COUNTER_WIDTH = count_width(DEBOUNCE_CYCLES);
    reg [2:0] key_meta;
    reg [2:0] key_sync;
    reg [1:0] sync_valid;
    reg [2:0] candidate;
    reg [2:0] armed;
    reg [COUNTER_WIDTH-1:0] debounce_count [0:2];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            key_meta <= 3'b111;
            key_sync <= 3'b111;
            sync_valid <= 2'b00;
            candidate <= 3'b111;
            armed <= 3'b000;
            timbre <= 2'd0;
            effect_on <= 1'b0;
            mode <= 2'd0;
            for (i = 0; i < 3; i = i + 1)
                debounce_count[i] <= 0;
        end else begin
            key_meta <= key;
            key_sync <= key_meta;
            sync_valid <= {sync_valid[0], 1'b1};

            // Ignore the reset values passing through the synchronizers.
            if (sync_valid[1]) begin
                for (i = 0; i < 3; i = i + 1) begin
                    if (key_sync[i] != candidate[i]) begin
                        candidate[i] <= key_sync[i];
                        debounce_count[i] <= 0;
                    end else if (debounce_count[i] < DEBOUNCE_CYCLES - 1) begin
                        debounce_count[i] <= debounce_count[i] + 1'b1;
                    end else if (candidate[i]) begin
                        armed[i] <= 1'b1;
                    end else if (armed[i]) begin
                        armed[i] <= 1'b0;
                        case (i)
                            0: timbre <= timbre + 1'b1;
                            1: effect_on <= effect_on + 1'b1;
                            2: mode <= (mode == 2'd2) ? 2'd0 : mode + 1'b1;
                        endcase
                    end
                end
            end
        end
    end
endmodule
