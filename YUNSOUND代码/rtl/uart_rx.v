`timescale 1ns/1ps

// UART receiver, 8 data bits, no parity, 1 stop bit, LSB first.
// The asynchronous RX pin passes through two flip-flops before sampling.
module uart_rx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 9600
)(
    input wire clk,
    input wire rst,
    input wire rx,
    output reg [7:0] data,
    output reg valid
);
    localparam integer BIT_CYCLES = CLK_HZ / BAUD;
    localparam [1:0] IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
    reg rx_meta, rx_sync;
    reg [1:0] state;
    reg [15:0] count;
    reg [2:0] bit_index;
    reg [7:0] shift;

    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            state <= IDLE;
            count <= 0;
            bit_index <= 0;
            shift <= 0;
            data <= 0;
            valid <= 1'b0;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
            valid <= 1'b0;
            case (state)
                IDLE: if (!rx_sync) begin
                    count <= BIT_CYCLES/2 - 1;
                    state <= START;
                end
                START: if (count != 0) count <= count - 1'b1;
                       else if (!rx_sync) begin
                           count <= BIT_CYCLES - 1;
                           bit_index <= 0;
                           state <= DATA;
                       end else state <= IDLE; // short noise pulse
                DATA: if (count != 0) count <= count - 1'b1;
                      else begin
                          shift[bit_index] <= rx_sync;
                          count <= BIT_CYCLES - 1;
                          if (bit_index == 3'd7) state <= STOP;
                          else bit_index <= bit_index + 1'b1;
                      end
                STOP: if (count != 0) count <= count - 1'b1;
                      else begin
                          if (rx_sync) begin
                              data <= shift;
                              valid <= 1'b1;
                          end
                          state <= IDLE;
                      end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
