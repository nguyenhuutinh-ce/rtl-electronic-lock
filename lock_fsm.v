module lock_fsm (
    input clk,
    input reset_n,
    input any_key,
    input match,
    input func_button,       // Phím '*' để đổi mật khẩu khi cửa đang mở
    input [2:0] digit_count,

    output reg clr_buffer,
    output reg load_new_pass,
    output reg green_led,
    output reg red_led,
    output reg buzzer,
    output reg [2:0] state_out
);

    // =========================
    // Định nghĩa trạng thái
    // =========================
    localparam S_IDLE        = 3'd0;
    localparam S_INPUTTING   = 3'd1;
    localparam S_CHECKING    = 3'd2;
    localparam S_UNLOCKED    = 3'd3;
    localparam S_WRONG_CODE  = 3'd4;
    localparam S_ALARM       = 3'd5;
    localparam S_CHANGE_PASS = 3'd6;

    // =========================
    // Thời gian delay với CLOCK_50 = 50MHz
    // =========================
    localparam INPUT_TIMEOUT = 32'd500_000_000;   // 10 giây
    localparam UNLOCK_DELAY  = 32'd500_000_000;   // 10 giây
    localparam WRONG_DELAY   = 32'd100_000_000;   // 2 giây hiện "SAI MA! THU LAI"
    localparam ALARM_DELAY   = 32'd1_500_000_000; // 30 giây báo động

    localparam WRONG_LIMIT   = 2'd3;              // Sai 3 lần thì báo động

    reg [2:0] current_state;
    reg [2:0] next_state;
    reg [31:0] timer;
    reg [1:0] wrong_cnt;

    // =========================
    // Thanh ghi trạng thái
    // =========================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            current_state <= S_IDLE;
        else
            current_state <= next_state;
    end

    // =========================
    // Timer và bộ đếm sai mật khẩu
    // =========================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            timer <= 32'd0;
            wrong_cnt <= 2'd0;
        end
        else begin
            // Khi đổi trạng thái thì reset timer
            if (current_state != next_state) begin
                timer <= 32'd0;

                // Nếu vừa kiểm tra xong và mã sai thì tăng số lần sai
                if (current_state == S_CHECKING && next_state == S_WRONG_CODE) begin
                    if (wrong_cnt < WRONG_LIMIT)
                        wrong_cnt <= wrong_cnt + 2'd1;
                    else
                        wrong_cnt <= wrong_cnt;
                end

                // Nếu mở khóa đúng hoặc hết báo động thì reset số lần sai
                if (current_state == S_CHECKING && next_state == S_UNLOCKED)
                    wrong_cnt <= 2'd0;

                if (current_state == S_ALARM && next_state == S_IDLE)
                    wrong_cnt <= 2'd0;
            end
            else begin
                timer <= timer + 32'd1;
            end
        end
    end

    // =========================
    // Logic chuyển trạng thái
    // =========================
    always @(*) begin
        next_state = current_state;

        clr_buffer = 1'b0;
        load_new_pass = 1'b0;

        case (current_state)

            // -------------------------
            // Chờ nhập mã
            // -------------------------
            S_IDLE: begin
                // Quan trọng:
                // Khi chưa bấm phím thì xóa buffer.
                // Khi vừa bấm phím đầu tiên thì KHÔNG xóa,
                // để password_manager nhận được số đầu tiên.
                clr_buffer = !any_key;

                if (any_key)
                    next_state = S_INPUTTING;
            end

            // -------------------------
            // Đang nhập 4 số
            // -------------------------
            S_INPUTTING: begin
                if (digit_count == 3'd4)
                    next_state = S_CHECKING;
                else if (timer >= INPUT_TIMEOUT)
                    next_state = S_IDLE;
            end

            // -------------------------
            // Kiểm tra mật khẩu
            // -------------------------
            S_CHECKING: begin
                if (match)
                    next_state = S_UNLOCKED;
                else
                    next_state = S_WRONG_CODE;
            end

            // -------------------------
            // Sai mã: giữ trạng thái này 2 giây
            // để LCD hiện "SAI MA! THU LAI"
            // -------------------------
            S_WRONG_CODE: begin
                if (timer >= WRONG_DELAY) begin
                    if (wrong_cnt >= WRONG_LIMIT)
                        next_state = S_ALARM;
                    else
                        next_state = S_IDLE;
                end
                else begin
                    next_state = S_WRONG_CODE;
                end
            end

            // -------------------------
            // Mở cửa
            // -------------------------
            S_UNLOCKED: begin
                if (func_button) begin
                    clr_buffer = 1'b1;
                    next_state = S_CHANGE_PASS;
                end
                else if (timer >= UNLOCK_DELAY) begin
                    next_state = S_IDLE;
                end
            end

            // -------------------------
            // Đổi mật khẩu mới
            // -------------------------
            S_CHANGE_PASS: begin
                if (digit_count == 3'd4) begin
                    load_new_pass = 1'b1;
                    next_state = S_IDLE;
                end
                else if (timer >= INPUT_TIMEOUT) begin
                    next_state = S_IDLE;
                end
            end

            // -------------------------
            // Báo động sau khi sai 3 lần
            // -------------------------
            S_ALARM: begin
                if (timer >= ALARM_DELAY)
                    next_state = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
            end

        endcase
    end

    // =========================
    // Output logic
    // =========================
    always @(*) begin
        green_led = 1'b0;
        red_led   = 1'b0;
        buzzer    = 1'b0;
        state_out = current_state;

        case (current_state)

            S_IDLE: begin
                red_led = 1'b1;
            end

            S_INPUTTING: begin
                red_led = 1'b1;
            end

            S_CHECKING: begin
                red_led = 1'b1;
            end

            S_UNLOCKED: begin
                green_led = 1'b1;
            end

            S_WRONG_CODE: begin
                red_led = 1'b1;
            end

            S_ALARM: begin
                red_led = 1'b1;
                buzzer = timer[24]; // Buzzer kêu nhấp nháy
            end

            S_CHANGE_PASS: begin
                green_led = 1'b1;
            end

            default: begin
                red_led = 1'b1;
            end

        endcase
    end

endmodule