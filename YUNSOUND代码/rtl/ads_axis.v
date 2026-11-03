`timescale 1ns/1ps
// ADS1115 divided joystick: raw ADC >>4 gives 2000 counts/V; endpoint .9V=1800.
// Unlike the internal-ADC mapping, each side is normalized to its own span.
// A restoring divider takes 17 clocks per non-neutral sample; keep adc_valid
// pulses at least 19 clocks apart (the MCP reader updates every 50000 clocks).
module ads_axis #(
    parameter integer MODE = 0,
    parameter integer CAL_SAMPLES = 32,
    parameter integer FULL_SCALE = 1800
) (
    input wire clk, rst, enable, adc_valid,
    input wire [13:0] adc_value,
    input wire sample_tick,
    output reg calibrated,
    output reg [13:0] center,
    output wire signed [8:0] modulation,
    output wire [6:0] expression_depth
);
    reg [21:0] cal_sum;
    reg [13:0] cal_min, cal_max;
    integer cal_count;
    reg signed [8:0] position;
    reg [31:0] lfo;
    wire [7:0] triangle_unsigned = lfo[31] ? (8'd255-lfo[30:23]) : lfo[30:23];
    wire signed [8:0] triangle = $signed({1'b0,triangle_unsigned}) - 9'sd128;
    wire [6:0] depth = position[8] ? -position : position;
    wire signed [16:0] vibrato_product = triangle * $signed({1'b0,depth});
    assign expression_depth = depth;
    assign modulation = (MODE == 0) ? position : (vibrato_product >>> 7);

    reg divide_busy, negative;
    reg [4:0] divide_count;
    reg [16:0] dividend, quotient;
    reg [10:0] divisor;
    reg [11:0] remainder;
    wire [11:0] trial_remainder = {remainder[10:0], dividend[16]};
    wire subtract = (trial_remainder >= {1'b0,divisor});
    wire [11:0] remainder_next = subtract ? (trial_remainder-{1'b0,divisor}) : trial_remainder;
    wire [16:0] quotient_next = {quotient[15:0],subtract};
    reg signed [8:0] target;
    integer diff, magnitude, error_pos;

    // Division by the constant 2 is only used for smoothing, never for the
    // variable ADC span. All values remain within -64..64.
    function signed [8:0] smooth;
        input signed [8:0] old_position, target_position;
        integer error_value;
        begin
            error_value = $signed(target_position)-$signed(old_position);
            if (error_value >= 2 || error_value <= -2)
                smooth = old_position + (error_value/2);
            else if (error_value > 0) smooth = old_position + 1'b1;
            else if (error_value < 0) smooth = old_position - 1'b1;
            else smooth = old_position;
        end
    endfunction

    always @(posedge clk) begin
        if (rst || !enable || (adc_valid && adc_value > 14'd2047)) begin
            calibrated <= 0;
            center <= 0;
            cal_sum <= 0;
            cal_min <= 16383;
            cal_max <= 0;
            cal_count <= 0;
            position <= 0;
            lfo <= 0;
            divide_busy <= 0;
            divide_count <= 0;
            negative <= 0;
            dividend <= 0;
            quotient <= 0;
            divisor <= 1;
            remainder <= 0;
            target <= 0;
        end else begin
            if (sample_tick) lfo <= lfo + 32'd447392; // ~5 Hz at 48 kHz
            if (adc_valid && !calibrated) begin
                if (adc_value < 256 || adc_value > 1536) begin
                    cal_count <= 0;
                    cal_sum <= 0;
                    cal_min <= 16383;
                    cal_max <= 0;
                end else if (cal_count == CAL_SAMPLES-1) begin
                    if ((cal_max-cal_min)<=48 && adc_value+48>=cal_max && adc_value<=cal_min+48) begin
                        center <= (cal_sum+adc_value)/CAL_SAMPLES;
                        calibrated <= 1;
                        position <= 0;
                    end
                    cal_count <= 0;
                    cal_sum <= 0;
                    cal_min <= 16383;
                    cal_max <= 0;
                end else begin
                    cal_count <= cal_count + 1;
                    cal_sum <= cal_sum + adc_value;
                    if (adc_value < cal_min) cal_min <= adc_value;
                    if (adc_value > cal_max) cal_max <= adc_value;
                end
            end
            if (adc_valid && calibrated && !divide_busy) begin
                diff = $signed({1'b0,adc_value})-$signed({1'b0,center});
                if (diff > 24 || diff < -24) begin
                    negative <= (diff < 0);
                    magnitude = (diff < 0) ? (-diff-24) : (diff-24);
                    dividend <= magnitude << 6;
                    divisor <= (diff < 0) ? (center-14'd24) : (FULL_SCALE-center-14'd24);
                    quotient <= 0;
                    remainder <= 0;
                    divide_count <= 17;
                    divide_busy <= 1;
                end else position <= smooth(position, 9'sd0);
            end
            if (divide_busy) begin
                dividend <= {dividend[15:0],1'b0};
                quotient <= quotient_next;
                remainder <= remainder_next;
                if (divide_count == 1) begin
                    divide_busy <= 0;
                    divide_count <= 0;
                    // The clamp also makes the bound explicit to synthesis.
                    if (quotient_next >= 64) target = negative ? -9'sd64 : 9'sd64;
                    else target = negative ? -$signed({1'b0,quotient_next[7:0]}) : $signed({1'b0,quotient_next[7:0]});
                    position <= smooth(position, target);
                end else divide_count <= divide_count - 1'b1;
            end
        end
    end
endmodule
