module lcd_driver #(
    parameter [6:0] I2C_ADDR = 7'h27  
)(
    input clk,               // CLOCK_50
    input reset_n,           // KEY[0]
    input [127:0] data_in,   // Chuoi 16 ky tu can hien thi len dong 1

    // I2C open-drain signals ra top-level
    input  sda_in,
    output sda_drive_low,
    output scl_drive_low
);

    // PCF8574 mapping thong dung:
    // P0=RS, P1=RW, P2=E, P3=Backlight, P4=D4, P5=D5, P6=D6, P7=D7
    localparam integer WAIT_POWER   = 1000000;   // 20 ms @ 50 MHz
    localparam integer WAIT_5MS     = 250000;
    localparam integer WAIT_2MS     = 100000;
    localparam integer WAIT_50US    = 2500;
    localparam integer WAIT_200US   = 10000;
    localparam integer WAIT_REFRESH = 5000000;   // 100 ms

    localparam [4:0]
        ST_POWER        = 5'd0,
        ST_INIT_NIB     = 5'd1,
        ST_INIT_NEXT    = 5'd2,
        ST_INIT_CMD     = 5'd3,
        ST_UPDATE_ADDR  = 5'd4,
        ST_DATA_LOAD    = 5'd5,
        ST_REFRESH_WAIT = 5'd6,
        ST_BYTE_START   = 5'd7,
        ST_BYTE_LOW     = 5'd8,
        ST_SEND_E1      = 5'd9,
        ST_WAIT_E1      = 5'd10,
        ST_SEND_E0      = 5'd11,
        ST_WAIT_E0      = 5'd12,
        ST_POST_NIB     = 5'd13;

    reg [4:0] state;
    reg [4:0] return_state;
    reg [4:0] byte_return_state;

    reg [31:0] cnt;
    reg [31:0] post_delay;

    reg [2:0] init_step;
    reg [2:0] init_cmd_idx;
    reg [4:0] char_idx;

    reg [7:0] cur_byte;
    reg byte_rs;
    reg [3:0] cur_nibble;
    reg cur_rs;

    reg tx_start;
    reg [7:0] tx_data;
    wire tx_busy;
    wire tx_done;

    i2c_write_byte #(
        .DIVIDER(250) // I2C cham, an toan cho LCD PCF8574 voi CLOCK_50
    ) i2c_inst (
        .clk(clk),
        .reset_n(reset_n),
        .start(tx_start),
        .addr(I2C_ADDR),
        .data(tx_data),
        .sda_in(sda_in),
        .busy(tx_busy),
        .done(tx_done),
        .sda_drive_low(sda_drive_low),
        .scl_drive_low(scl_drive_low)
    );

    function [7:0] pcf_byte;
        input [3:0] nibble;
        input rs;
        input en;
        begin
            // {D7,D6,D5,D4, Backlight, E, RW, RS}
            pcf_byte = {nibble, 1'b1, en, 1'b0, rs};
        end
    endfunction

    function [7:0] init_cmd;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: init_cmd = 8'h28; // 4-bit, 2 dong, font 5x8
                3'd1: init_cmd = 8'h0C; // display ON, cursor OFF
                3'd2: init_cmd = 8'h01; // clear display
                3'd3: init_cmd = 8'h06; // entry mode
                default: init_cmd = 8'h80;
            endcase
        end
    endfunction

    function [7:0] char_at;
        input [127:0] s;
        input [4:0] pos;
        begin
            case (pos)
                5'd0:  char_at = s[127:120];
                5'd1:  char_at = s[119:112];
                5'd2:  char_at = s[111:104];
                5'd3:  char_at = s[103:96];
                5'd4:  char_at = s[95:88];
                5'd5:  char_at = s[87:80];
                5'd6:  char_at = s[79:72];
                5'd7:  char_at = s[71:64];
                5'd8:  char_at = s[63:56];
                5'd9:  char_at = s[55:48];
                5'd10: char_at = s[47:40];
                5'd11: char_at = s[39:32];
                5'd12: char_at = s[31:24];
                5'd13: char_at = s[23:16];
                5'd14: char_at = s[15:8];
                5'd15: char_at = s[7:0];
                default: char_at = 8'h20;
            endcase
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= ST_POWER;
            return_state <= ST_POWER;
            byte_return_state <= ST_POWER;

            cnt <= 32'd0;
            post_delay <= 32'd0;

            init_step <= 3'd0;
            init_cmd_idx <= 3'd0;
            char_idx <= 5'd0;

            cur_byte <= 8'h00;
            byte_rs <= 1'b0;
            cur_nibble <= 4'h0;
            cur_rs <= 1'b0;

            tx_start <= 1'b0;
            tx_data <= 8'h00;
        end else begin
            tx_start <= 1'b0;

            case (state)
                ST_POWER: begin
                    if (cnt < WAIT_POWER) begin
                        cnt <= cnt + 32'd1;
                    end else begin
                        cnt <= 32'd0;
                        init_step <= 3'd0;
                        state <= ST_INIT_NIB;
                    end
                end

                // Chuoi init dac biet de vao che do 4-bit: 3,3,3,2
                ST_INIT_NIB: begin
                    cur_rs <= 1'b0;
                    return_state <= ST_INIT_NEXT;

                    case (init_step)
                        3'd0: begin cur_nibble <= 4'h3; post_delay <= WAIT_5MS;   state <= ST_SEND_E1; end
                        3'd1: begin cur_nibble <= 4'h3; post_delay <= WAIT_200US; state <= ST_SEND_E1; end
                        3'd2: begin cur_nibble <= 4'h3; post_delay <= WAIT_200US; state <= ST_SEND_E1; end
                        3'd3: begin cur_nibble <= 4'h2; post_delay <= WAIT_200US; state <= ST_SEND_E1; end
                        default: begin
                            init_cmd_idx <= 3'd0;
                            state <= ST_INIT_CMD;
                        end
                    endcase
                end

                ST_INIT_NEXT: begin
                    init_step <= init_step + 3'd1;
                    state <= ST_INIT_NIB;
                end

                ST_INIT_CMD: begin
                    if (init_cmd_idx < 3'd4) begin
                        cur_byte <= init_cmd(init_cmd_idx);
                        byte_rs <= 1'b0;
                        byte_return_state <= ST_INIT_CMD;
                        init_cmd_idx <= init_cmd_idx + 3'd1;
                        state <= ST_BYTE_START;
                    end else begin
                        state <= ST_UPDATE_ADDR;
                    end
                end

                // Moi vong cap nhat: dua con tro ve dau dong 1 roi ghi 16 ky tu
                ST_UPDATE_ADDR: begin
                    cur_byte <= 8'h80;
                    byte_rs <= 1'b0;
                    byte_return_state <= ST_DATA_LOAD;
                    char_idx <= 5'd0;
                    state <= ST_BYTE_START;
                end

                ST_DATA_LOAD: begin
                    if (char_idx < 5'd16) begin
                        cur_byte <= char_at(data_in, char_idx);
                        byte_rs <= 1'b1;
                        byte_return_state <= ST_DATA_LOAD;
                        char_idx <= char_idx + 5'd1;
                        state <= ST_BYTE_START;
                    end else begin
                        cnt <= 32'd0;
                        state <= ST_REFRESH_WAIT;
                    end
                end

                ST_REFRESH_WAIT: begin
                    if (cnt < WAIT_REFRESH) begin
                        cnt <= cnt + 32'd1;
                    end else begin
                        cnt <= 32'd0;
                        state <= ST_UPDATE_ADDR;
                    end
                end

                // Gui 1 byte LCD thanh 2 nibble
                ST_BYTE_START: begin
                    cur_nibble <= cur_byte[7:4];
                    cur_rs <= byte_rs;
                    post_delay <= WAIT_50US;
                    return_state <= ST_BYTE_LOW;
                    state <= ST_SEND_E1;
                end

                ST_BYTE_LOW: begin
                    cur_nibble <= cur_byte[3:0];
                    cur_rs <= byte_rs;
                    if ((cur_byte == 8'h01) || (cur_byte == 8'h02))
                        post_delay <= WAIT_2MS;
                    else
                        post_delay <= WAIT_50US;
                    return_state <= byte_return_state;
                    state <= ST_SEND_E1;
                end

                // Gui 1 nibble qua PCF8574: E=1 roi E=0
                ST_SEND_E1: begin
                    if (!tx_busy) begin
                        tx_data <= pcf_byte(cur_nibble, cur_rs, 1'b1);
                        tx_start <= 1'b1;
                        state <= ST_WAIT_E1;
                    end
                end

                ST_WAIT_E1: begin
                    if (tx_done)
                        state <= ST_SEND_E0;
                end

                ST_SEND_E0: begin
                    if (!tx_busy) begin
                        tx_data <= pcf_byte(cur_nibble, cur_rs, 1'b0);
                        tx_start <= 1'b1;
                        state <= ST_WAIT_E0;
                    end
                end

                ST_WAIT_E0: begin
                    if (tx_done) begin
                        cnt <= 32'd0;
                        state <= ST_POST_NIB;
                    end
                end

                ST_POST_NIB: begin
                    if (cnt < post_delay) begin
                        cnt <= cnt + 32'd1;
                    end else begin
                        cnt <= 32'd0;
                        state <= return_state;
                    end
                end

                default: state <= ST_POWER;
            endcase
        end
    end

endmodule


module i2c_write_byte #(
    parameter integer DIVIDER = 250
)(
    input clk,
    input reset_n,

    input start,
    input [6:0] addr,
    input [7:0] data,

    input sda_in,

    output reg busy,
    output reg done,

    output reg sda_drive_low,
    output reg scl_drive_low
);

    localparam [3:0]
        S_IDLE      = 4'd0,
        S_START1    = 4'd1,
        S_START2    = 4'd2,
        S_START3    = 4'd3,
        S_BIT_SETUP = 4'd4,
        S_BIT_HIGH  = 4'd5,
        S_BIT_LOW   = 4'd6,
        S_ACK_SETUP = 4'd7,
        S_ACK_HIGH  = 4'd8,
        S_ACK_LOW   = 4'd9,
        S_STOP1     = 4'd10,
        S_STOP2     = 4'd11,
        S_STOP3     = 4'd12,
        S_DONE      = 4'd13;

    reg [3:0] state;
    reg [31:0] div_cnt;

    reg [15:0] shreg;
    reg [4:0] bit_pos;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            div_cnt <= 32'd0;
            shreg <= 16'd0;
            bit_pos <= 5'd0;
            busy <= 1'b0;
            done <= 1'b0;
            sda_drive_low <= 1'b0;
            scl_drive_low <= 1'b0;
        end else begin
            done <= 1'b0;

            if (state == S_IDLE) begin
                div_cnt <= 32'd0;
                sda_drive_low <= 1'b0; // tha SDA
                scl_drive_low <= 1'b0; // tha SCL
                busy <= 1'b0;

                if (start) begin
                    shreg <= {addr, 1'b0, data}; // address + write bit + data
                    bit_pos <= 5'd15;
                    busy <= 1'b1;
                    state <= S_START1;
                end
            end else begin
                if (div_cnt < DIVIDER - 1) begin
                    div_cnt <= div_cnt + 32'd1;
                end else begin
                    div_cnt <= 32'd0;

                    case (state)
                        S_START1: begin
                            sda_drive_low <= 1'b0;
                            scl_drive_low <= 1'b0;
                            state <= S_START2;
                        end

                        S_START2: begin
                            sda_drive_low <= 1'b1; // START: SDA xuong 0 khi SCL dang 1
                            scl_drive_low <= 1'b0;
                            state <= S_START3;
                        end

                        S_START3: begin
                            sda_drive_low <= 1'b1;
                            scl_drive_low <= 1'b1; // keo SCL xuong
                            state <= S_BIT_SETUP;
                        end

                        S_BIT_SETUP: begin
                            scl_drive_low <= 1'b1;
                            if (shreg[bit_pos] == 1'b0)
                                sda_drive_low <= 1'b1;
                            else
                                sda_drive_low <= 1'b0;
                            state <= S_BIT_HIGH;
                        end

                        S_BIT_HIGH: begin
                            scl_drive_low <= 1'b0; // tha SCL len 1
                            state <= S_BIT_LOW;
                        end

                        S_BIT_LOW: begin
                            scl_drive_low <= 1'b1; // keo SCL xuong
                            if ((bit_pos == 5'd8) || (bit_pos == 5'd0)) begin
                                state <= S_ACK_SETUP;
                            end else begin
                                bit_pos <= bit_pos - 5'd1;
                                state <= S_BIT_SETUP;
                            end
                        end

                        S_ACK_SETUP: begin
                            sda_drive_low <= 1'b0; // tha SDA de slave ACK
                            scl_drive_low <= 1'b1;
                            state <= S_ACK_HIGH;
                        end

                        S_ACK_HIGH: begin
                            scl_drive_low <= 1'b0; // lay mau ACK, hien tai khong bat loi
                            state <= S_ACK_LOW;
                        end

                        S_ACK_LOW: begin
                            scl_drive_low <= 1'b1;
                            if (bit_pos == 5'd8) begin
                                bit_pos <= 5'd7;
                                state <= S_BIT_SETUP;
                            end else begin
                                state <= S_STOP1;
                            end
                        end

                        S_STOP1: begin
                            sda_drive_low <= 1'b1;
                            scl_drive_low <= 1'b1;
                            state <= S_STOP2;
                        end

                        S_STOP2: begin
                            sda_drive_low <= 1'b1;
                            scl_drive_low <= 1'b0; // tha SCL len 1
                            state <= S_STOP3;
                        end

                        S_STOP3: begin
                            sda_drive_low <= 1'b0; // STOP: SDA len 1 khi SCL dang 1
                            scl_drive_low <= 1'b0;
                            state <= S_DONE;
                        end

                        S_DONE: begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            state <= S_IDLE;
                        end

                        default: state <= S_IDLE;
                    endcase
                end
            end
        end
    end

endmodule
