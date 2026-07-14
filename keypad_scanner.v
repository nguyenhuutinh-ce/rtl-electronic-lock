module keypad_scanner (
    input clk,               // CLOCK_50
    input reset_n,           // KEY[0], active-low reset

    // Ket noi keypad 4x4 qua GPIO_0:
    // row_out[0] -> R1 -> GPIO_0[0]
    // row_out[1] -> R2 -> GPIO_0[1]
    // row_out[2] -> R3 -> GPIO_0[2]
    // row_out[3] -> R4 -> GPIO_0[3]
    // col_in[0]  -> C1 -> GPIO_0[4]
    // col_in[1]  -> C2 -> GPIO_0[5]
    // col_in[2]  -> C3 -> GPIO_0[6]
    // col_in[3]  -> C4 -> GPIO_0[7]
    input  [3:0] col_in,
    output reg [3:0] row_out,

    output reg [3:0] key_code,     // Ma phim: 0..9, A..D, E='*', F='#'
    output reg key_pressed         // Xung 1 chu ky clock khi phim vua duoc nhan on dinh
);

    // Moi hang giu 1 ms, doc cot sau 100 us de tin hieu on dinh
    localparam integer ROW_TICKS    = 50000; // 1 ms @ 50 MHz
    localparam integer SETTLE_TICKS = 5000;  // 100 us @ 50 MHz
    localparam integer DEBOUNCE_FRAMES = 5;  // 5 frame * 4 ms = ~20 ms

    reg [15:0] cnt;
    reg [1:0]  row_idx;

    wire [3:0] col_low;
    assign col_low = ~col_in; // cot nao bi keo xuong 0 thi bit tuong ung = 1

    // Ket qua trong 1 vong quet 4 hang
    reg frame_valid;
    reg [3:0] frame_code;

    // Mau truoc do de debounce
    reg prev_sample_valid;
    reg [3:0] prev_sample_code;
    reg [3:0] stable_cnt;

    // Trang thai phim da debounce
    reg debounced_valid;
    reg [3:0] debounced_code;

    wire [4:0] decoded;
    wire decoded_valid;
    wire [3:0] decoded_code;

    assign decoded = decode_key(row_idx, col_low);
    assign decoded_valid = decoded[4];
    assign decoded_code  = decoded[3:0];

    function [3:0] row_pattern;
        input [1:0] r;
        begin
            case (r)
                2'd0: row_pattern = 4'b1110; // quet R1: R1 = 0
                2'd1: row_pattern = 4'b1101; // quet R2: R2 = 0
                2'd2: row_pattern = 4'b1011; // quet R3: R3 = 0
                2'd3: row_pattern = 4'b0111; // quet R4: R4 = 0
                default: row_pattern = 4'b1111;
            endcase
        end
    endfunction

    function [4:0] decode_key;
        input [1:0] row;
        input [3:0] col;
        begin
            decode_key = {1'b0, 4'h0};

            case (row)
                // Hang 1: 1 2 3 A
                2'd0: begin
                    if      (col[0]) decode_key = {1'b1, 4'h1};
                    else if (col[1]) decode_key = {1'b1, 4'h2};
                    else if (col[2]) decode_key = {1'b1, 4'h3};
                    else if (col[3]) decode_key = {1'b1, 4'hA};
                end

                // Hang 2: 4 5 6 B
                2'd1: begin
                    if      (col[0]) decode_key = {1'b1, 4'h4};
                    else if (col[1]) decode_key = {1'b1, 4'h5};
                    else if (col[2]) decode_key = {1'b1, 4'h6};
                    else if (col[3]) decode_key = {1'b1, 4'hB};
                end

                // Hang 3: 7 8 9 C
                2'd2: begin
                    if      (col[0]) decode_key = {1'b1, 4'h7};
                    else if (col[1]) decode_key = {1'b1, 4'h8};
                    else if (col[2]) decode_key = {1'b1, 4'h9};
                    else if (col[3]) decode_key = {1'b1, 4'hC};
                end

                // Hang 4: * 0 # D
                2'd3: begin
                    if      (col[0]) decode_key = {1'b1, 4'hE}; // *
                    else if (col[1]) decode_key = {1'b1, 4'h0}; // 0
                    else if (col[2]) decode_key = {1'b1, 4'hF}; // #
                    else if (col[3]) decode_key = {1'b1, 4'hD};
                end
            endcase
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cnt <= 16'd0;
            row_idx <= 2'd0;
            row_out <= 4'b1110;

            frame_valid <= 1'b0;
            frame_code  <= 4'h0;

            prev_sample_valid <= 1'b0;
            prev_sample_code  <= 4'h0;
            stable_cnt <= 4'd0;

            debounced_valid <= 1'b0;
            debounced_code  <= 4'h0;

            key_code <= 4'h0;
            key_pressed <= 1'b0;
        end else begin
            key_pressed <= 1'b0;

            // Doc cot sau khi doi hang duoc 100 us
            if (cnt == SETTLE_TICKS) begin
                if (decoded_valid && !frame_valid) begin
                    frame_valid <= 1'b1;
                    frame_code  <= decoded_code;
                end
            end

            // Het thoi gian cho hang hien tai
            if (cnt == ROW_TICKS - 1) begin
                cnt <= 16'd0;

                if (row_idx == 2'd3) begin
                    // Ket thuc 1 frame gom 4 hang
                    if ((frame_valid == prev_sample_valid) &&
                        ((!frame_valid) || (frame_code == prev_sample_code))) begin

                        if (stable_cnt < DEBOUNCE_FRAMES)
                            stable_cnt <= stable_cnt + 4'd1;

                        // Khi mau da on dinh du DEBOUNCE_FRAMES
                        if (stable_cnt == DEBOUNCE_FRAMES - 1) begin
                            if ((debounced_valid != frame_valid) ||
                                (frame_valid && (debounced_code != frame_code))) begin

                                debounced_valid <= frame_valid;
                                debounced_code  <= frame_code;

                                if (frame_valid) begin
                                    key_code <= frame_code;
                                    key_pressed <= 1'b1;
                                end
                            end
                        end
                    end else begin
                        stable_cnt <= 4'd0;
                    end

                    prev_sample_valid <= frame_valid;
                    prev_sample_code  <= frame_code;

                    frame_valid <= 1'b0;
                    frame_code  <= 4'h0;

                    row_idx <= 2'd0;
                    row_out <= row_pattern(2'd0);
                end else begin
                    row_idx <= row_idx + 2'd1;
                    row_out <= row_pattern(row_idx + 2'd1);
                end
            end else begin
                cnt <= cnt + 16'd1;
            end
        end
    end

endmodule
