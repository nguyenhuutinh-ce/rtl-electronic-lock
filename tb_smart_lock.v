`timescale 1ns/1ps

module tb_smart_lock;

    reg CLOCK_50;
    reg [3:0] KEY;
    wire [35:0] GPIO_0;
    wire [35:0] GPIO_1;
    wire [8:0] LEDG;
    wire [17:0] LEDR;

    smart_lock dut (
        .CLOCK_50(CLOCK_50),
        .KEY(KEY),
        .GPIO_0(GPIO_0),
        .GPIO_1(GPIO_1),
        .LEDG(LEDG),
        .LEDR(LEDR)
    );

    // Clock 50 MHz, chu ky 20 ns
    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    // Cac gia tri delay trong lock_fsm
    // Dung dung nguong delay, khong force 32'hFFFF_FFFF de tranh vuot qua S_ALARM.
    localparam [31:0] WRONG_DELAY_VALUE  = 32'd100_000_000;
    localparam [31:0] UNLOCK_DELAY_VALUE = 32'd500_000_000;

    // Ma trang thai trong lock_fsm
    localparam [2:0] S_IDLE        = 3'd0;
    localparam [2:0] S_INPUTTING   = 3'd1;
    localparam [2:0] S_CHECKING    = 3'd2;
    localparam [2:0] S_UNLOCKED    = 3'd3;
    localparam [2:0] S_WRONG_CODE  = 3'd4;
    localparam [2:0] S_ALARM       = 3'd5;
    localparam [2:0] S_CHANGE_PASS = 3'd6;

    // Tao 1 xung phim nhan bang cach force tin hieu noi bo cua top
    task press_key;
        input [3:0] key;
        begin
            @(negedge CLOCK_50);
            force dut.w_key_code    = key;
            force dut.w_key_pressed = 1'b1;
            @(negedge CLOCK_50);
            force dut.w_key_pressed = 1'b0;
            repeat (3) @(negedge CLOCK_50);
        end
    endtask

    task enter_code;
        input [3:0] k1, k2, k3, k4;
        begin
            press_key(k1);
            press_key(k2);
            press_key(k3);
            press_key(k4);
            repeat (5) @(negedge CLOCK_50);
        end
    endtask

    // Tang nhanh timer de FSM thoat khoi trang thai delay.
    // Luu y: force dung nguong can thiet, sau do release ngay sau canh clock.
    // Neu force 32'hFFFF_FFFF, khi vao S_ALARM timer van qua lon va FSM co the thoat S_ALARM ngay.
    task jump_timer;
        input [31:0] value;
        begin
            @(negedge CLOCK_50);
            force dut.controller_inst.timer = value;
            @(posedge CLOCK_50);
            #1;
            release dut.controller_inst.timer;
            repeat (3) @(negedge CLOCK_50);
        end
    endtask

    task skip_wrong_delay;
        begin
            jump_timer(WRONG_DELAY_VALUE);
        end
    endtask

    task skip_unlock_delay;
        begin
            jump_timer(UNLOCK_DELAY_VALUE);
        end
    endtask

    task show_status;
        input [160*8:1] msg;
        begin
            $display("[%0t ns] %0s | state=%0d wrong_cnt=%0d timer=%0d count=%0d match=%b LEDG0=%b LEDR0=%b buzzer=%b saved_pass=%h buffer=%h lcd='%s'",
                     $time, msg,
                     dut.controller_inst.state_out,
                     dut.controller_inst.wrong_cnt,
                     dut.controller_inst.timer,
                     dut.pass_inst.count,
                     dut.pass_inst.match,
                     LEDG[0], LEDR[0], GPIO_1[2],
                     dut.pass_inst.saved_pass,
                     dut.pass_inst.buffer,
                     dut.w_lcd_string);
        end
    endtask

    initial begin
        $display("===== BAT DAU MO PHONG SMART LOCK =====");

        // Reset he thong, KEY[0] active-low
        KEY = 4'b1110;
        repeat (5) @(negedge CLOCK_50);
        KEY[0] = 1'b1;
        repeat (5) @(negedge CLOCK_50);
        show_status("Sau reset");

        // TEST 1: Nhap mat khau mac dinh 1234 -> mo khoa
        $display("\n--- TEST 1: Nhap dung mat khau 1234 ---");
        enter_code(4'h1, 4'h2, 4'h3, 4'h4);
        repeat (5) @(negedge CLOCK_50);
        show_status("Sau khi nhap 1234");

        if (dut.controller_inst.state_out == S_UNLOCKED && LEDG[0] == 1'b1)
            $display("PASS TEST 1: Dung mat khau -> cua mo, LED xanh sang.");
        else
            $display("FAIL TEST 1: Chua vao S_UNLOCKED.");

        // TEST 2: Khi dang mo khoa, bam '*' roi nhap ma moi 5678
        $display("\n--- TEST 2: Doi mat khau moi thanh 5678 ---");
        press_key(4'hE); // phim '*'
        repeat (5) @(negedge CLOCK_50);
        show_status("Sau khi bam * de vao che do doi ma");

        enter_code(4'h5, 4'h6, 4'h7, 4'h8);
        repeat (5) @(negedge CLOCK_50);
        show_status("Sau khi nhap ma moi 5678");

        if (dut.pass_inst.saved_pass == 16'h5678)
            $display("PASS TEST 2: Da luu mat khau moi 5678.");
        else
            $display("FAIL TEST 2: Chua luu dung mat khau moi.");

        // TEST 3: Nhap lai ma cu 1234 -> sai
        $display("\n--- TEST 3: Nhap lai ma cu 1234, yeu cau phai sai ---");
        enter_code(4'h1, 4'h2, 4'h3, 4'h4);
        repeat (5) @(negedge CLOCK_50);
        show_status("Sau khi nhap lai ma cu 1234");

        if (dut.controller_inst.state_out == S_WRONG_CODE)
            $display("PASS TEST 3: Ma cu bi tu choi, vao S_WRONG_CODE.");
        else
            $display("FAIL TEST 3: Ma cu khong bi tu choi nhu mong doi.");

        skip_wrong_delay();
        show_status("Sau khi bo qua WRONG_DELAY");

        // TEST 4: Nhap ma moi 5678 -> mo khoa
        $display("\n--- TEST 4: Nhap ma moi 5678 ---");
        enter_code(4'h5, 4'h6, 4'h7, 4'h8);
        repeat (5) @(negedge CLOCK_50);
        show_status("Sau khi nhap ma moi 5678");

        if (dut.controller_inst.state_out == S_UNLOCKED && LEDG[0] == 1'b1)
            $display("PASS TEST 4: Mat khau moi dung -> cua mo.");
        else
            $display("FAIL TEST 4: Mat khau moi khong mo khoa.");

        // TEST 5: Nhap sai 3 lan -> bao dong
        $display("\n--- TEST 5: Sai 3 lan de kiem tra bao dong ---");
        skip_unlock_delay(); // tu S_UNLOCKED ve S_IDLE
        show_status("Sau khi bo qua UNLOCK_DELAY, san sang test bao dong");

        enter_code(4'h0, 4'h0, 4'h0, 4'h0);
        repeat (5) @(negedge CLOCK_50);
        show_status("Sai lan 1");
        skip_wrong_delay();
        show_status("Sau WRONG_DELAY lan 1");

        enter_code(4'h1, 4'h1, 4'h1, 4'h1);
        repeat (5) @(negedge CLOCK_50);
        show_status("Sai lan 2");
        skip_wrong_delay();
        show_status("Sau WRONG_DELAY lan 2");

        enter_code(4'h2, 4'h2, 4'h2, 4'h2);
        repeat (5) @(negedge CLOCK_50);
        show_status("Sai lan 3");
        skip_wrong_delay();
        show_status("Sau WRONG_DELAY lan 3");

        if (dut.controller_inst.state_out == S_ALARM)
            $display("PASS TEST 5: Sai 3 lan -> vao S_ALARM.");
        else
            $display("FAIL TEST 5: Chua vao S_ALARM. Kiem tra wrong_cnt va timer tren waveform.");

        $display("\n===== KET THUC MO PHONG =====");
        #100;
        $stop;
    end

endmodule
