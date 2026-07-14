module smart_lock (
    input CLOCK_50,
    input [3:0] KEY,

    // GPIO_0 dung cho keypad 4x4:
    // GPIO_0[0] R1, GPIO_0[1] R2, GPIO_0[2] R3, GPIO_0[3] R4
    // GPIO_0[4] C1, GPIO_0[5] C2, GPIO_0[6] C3, GPIO_0[7] C4
    inout [35:0] GPIO_0,

    // GPIO_1 dung cho LCD I2C:
    // GPIO_1[0] SDA, GPIO_1[1] SCL
    // GPIO_1[2] buzzer 
    inout [35:0] GPIO_1,

    output [8:0] LEDG,
    output [17:0] LEDR
);

    wire reset_n;
    assign reset_n = KEY[0];

    // --- Day noi noi bo ---
    wire [3:0] w_key_code;
    wire w_key_pressed;
    wire w_match, w_clr, w_load;
    wire [2:0] w_digit_count, w_state;
    wire [127:0] w_lcd_string;
    wire w_buzzer;

    // --- Ket noi keypad vao GPIO_0 ---
    wire [3:0] kp_row_out;
    wire [3:0] kp_col_in;

    assign kp_col_in = GPIO_0[7:4];

    // Hang keypad la output tu FPGA
    assign GPIO_0[0] = kp_row_out[0];
    assign GPIO_0[1] = kp_row_out[1];
    assign GPIO_0[2] = kp_row_out[2];
    assign GPIO_0[3] = kp_row_out[3];

    // Cot keypad la input, can bat WEAK_PULL_UP trong file .qsf
    assign GPIO_0[7:4] = 4'bzzzz;

    // Khong dung cac chan GPIO_0 con lai
    assign GPIO_0[35:8] = 28'bzzzzzzzzzzzzzzzzzzzzzzzzzzzz;

    keypad_scanner scanner_inst (
        .clk(CLOCK_50),
        .reset_n(reset_n),
        .col_in(kp_col_in),
        .row_out(kp_row_out),
        .key_code(w_key_code),
        .key_pressed(w_key_pressed)
    );

    // Phim * dung de doi mat ma khi dang mo khoa
    wire w_func_btn;
    assign w_func_btn = (w_key_code == 4'hE) && w_key_pressed;

    password_manager pass_inst (
        .clk(CLOCK_50),
        .reset_n(reset_n),
        .key_in(w_key_code),
        .key_pressed(w_key_pressed),
        .clr_buffer(w_clr),
        .load_new_pass(w_load),
        .match(w_match),
        .count(w_digit_count)
    );

    lock_fsm controller_inst (
        .clk(CLOCK_50),
        .reset_n(reset_n),
        .any_key(w_key_pressed),
        .match(w_match),
        .func_button(w_func_btn),
        .digit_count(w_digit_count),
        .clr_buffer(w_clr),
        .load_new_pass(w_load),
        .green_led(LEDG[0]),
        .red_led(LEDR[0]),
        .buzzer(w_buzzer),
        .state_out(w_state)
    );

    lcd_interface lcd_int_inst (
        .state(w_state),
        .digit_count(w_digit_count),
        .lcd_string(w_lcd_string)
    );

    // --- Ket noi LCD I2C vao GPIO_1 ---
    wire sda_drive_low;
    wire scl_drive_low;

    assign GPIO_1[0] = sda_drive_low ? 1'b0 : 1'bz; // SDA open-drain
    assign GPIO_1[1] = scl_drive_low ? 1'b0 : 1'bz; // SCL open-drain

    assign GPIO_1[2] = w_buzzer;
    assign GPIO_1[35:3] = 33'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz;

    lcd_driver #(
        .I2C_ADDR(7'h27) 
    ) lcd_drv_inst (
        .clk(CLOCK_50),
        .reset_n(reset_n),
        .data_in(w_lcd_string),
        .sda_in(GPIO_1[0]),
        .sda_drive_low(sda_drive_low),
        .scl_drive_low(scl_drive_low)
    );

    // Tat cac LED khong dung
    assign LEDG[8:1] = 8'b00000000;
    assign LEDR[17:1] = 17'b00000000000000000;

endmodule
