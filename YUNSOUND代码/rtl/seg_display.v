`timescale 1ns/1ps

// ACG525-CB schematic page 10: DIO -> U13 (digit selects) -> U14
// (A,B,C,D,E,F,G,DP), so transmit {segments, selects}, MSB first.
// Common-anode displays: segments active LOW, digit selects active HIGH.
// digits[3:0] is the rightmost digit (HEX_SEL0); F is blank.
// Each new digit is preceded by a latched all-off frame to avoid ghosting.
module seg_display #(
    parameter integer HALF_CLK_CYCLES = 25,
    parameter integer HOLD_CYCLES = 12500
) (
    input wire clk,
    input wire rst,
    input wire [31:0] digits,
    output reg dio,
    output reg sclk,
    output reg rclk
);
    localparam LOAD_BLANK = 3'd0;
    localparam LOAD_DIGIT = 3'd1;
    localparam SHIFT_HIGH = 3'd2;
    localparam SHIFT_LOW = 3'd3;
    localparam LATCH_HIGH = 3'd4;
    localparam LATCH_LOW = 3'd5;
    localparam HOLD = 3'd6;
    reg [2:0] state;
    reg [2:0] digit_index;
    reg [15:0] shift_word;
    reg [3:0] bit_index;
    reg blank_frame;
    reg [31:0] divider;
    reg [31:0] hold_counter;

    function [7:0] font;
        input [3:0] digit;
        begin
            case (digit)
                4'h0: font = 8'hc0;
                4'h1: font = 8'hf9;
                4'h2: font = 8'ha4;
                4'h3: font = 8'hb0;
                4'h4: font = 8'h99;
                4'h5: font = 8'h92;
                4'h6: font = 8'h82;
                4'h7: font = 8'hf8;
                4'h8: font = 8'h80;
                4'h9: font = 8'h90;
                4'ha: font = 8'h88;
                4'hb: font = 8'h83;
                4'hc: font = 8'hc6;
                4'hd: font = 8'ha1;
                4'he: font = 8'h86;
                default: font = 8'hff;
            endcase
        end
    endfunction

    wire [31:0] shifted_digits = digits >> {digit_index, 2'b00};
    wire [7:0] segment_pattern = font(shifted_digits[3:0]);
    wire [7:0] digit_select = 8'b00000001 << digit_index;

    always @(posedge clk) begin
        if (rst) begin
            state <= LOAD_BLANK;
            digit_index <= 3'd0;
            shift_word <= 16'hff00;
            bit_index <= 4'd15;
            blank_frame <= 1'b1;
            divider <= 0;
            hold_counter <= 0;
            dio <= 1'b0;
            sclk <= 1'b0;
            rclk <= 1'b0;
        end else begin
            case (state)
                LOAD_BLANK: begin
                    shift_word <= 16'hff00;
                    dio <= 1'b1;
                    sclk <= 1'b0;
                    rclk <= 1'b0;
                    bit_index <= 4'd15;
                    divider <= 0;
                    blank_frame <= 1'b1;
                    state <= SHIFT_HIGH;
                end
                LOAD_DIGIT: begin
                    shift_word <= {segment_pattern, digit_select};
                    dio <= segment_pattern[7];
                    bit_index <= 4'd15;
                    divider <= 0;
                    blank_frame <= 1'b0;
                    state <= SHIFT_HIGH;
                end
                HOLD: begin
                    if (hold_counter >= HOLD_CYCLES - 1) begin
                        hold_counter <= 0;
                        digit_index <= digit_index + 1'b1;
                        state <= LOAD_BLANK;
                    end else begin
                        hold_counter <= hold_counter + 1'b1;
                    end
                end
                default: begin
                    if (divider >= HALF_CLK_CYCLES - 1) begin
                        divider <= 0;
                        case (state)
                            SHIFT_HIGH: begin
                                sclk <= 1'b1;
                                state <= SHIFT_LOW;
                            end
                            SHIFT_LOW: begin
                                sclk <= 1'b0;
                                if (bit_index == 0) begin
                                    state <= LATCH_HIGH;
                                end else begin
                                    shift_word <= {shift_word[14:0], 1'b0};
                                    dio <= shift_word[14];
                                    bit_index <= bit_index - 1'b1;
                                    state <= SHIFT_HIGH;
                                end
                            end
                            LATCH_HIGH: begin
                                rclk <= 1'b1;
                                state <= LATCH_LOW;
                            end
                            LATCH_LOW: begin
                                rclk <= 1'b0;
                                if (blank_frame)
                                    state <= LOAD_DIGIT;
                                else begin
                                    hold_counter <= 0;
                                    state <= HOLD;
                                end
                            end
                            default: state <= LOAD_BLANK;
                        endcase
                    end else begin
                        divider <= divider + 1'b1;
                    end
                end
            endcase
        end
    end
endmodule
