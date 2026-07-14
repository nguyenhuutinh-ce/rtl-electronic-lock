module lcd_interface (
    input [2:0] state,
    input [2:0] digit_count,
    output reg [127:0] lcd_string
);

    always @(*) begin
        case (state)

            3'd0: lcd_string = "MOI NHAP MA     "; // S_IDLE

            3'd1: begin // S_INPUTTING
                case (digit_count)
                    3'd1:    lcd_string = "NHAP: *         ";
                    3'd2:    lcd_string = "NHAP: **        ";
                    3'd3:    lcd_string = "NHAP: ***       ";
                    3'd4:    lcd_string = "NHAP: ****      ";
                    default: lcd_string = "NHAP:           ";
                endcase
            end

            3'd2: lcd_string = "DANG KIEM TRA.. "; // S_CHECKING

            3'd3: lcd_string = "CUA DA MO!      "; // S_UNLOCKED

            3'd4: lcd_string = "SAI MA! THU LAI "; // S_WRONG_CODE

            3'd5: lcd_string = "HE THONG KHOA!  "; // S_ALARM

            3'd6: begin // S_CHANGE_PASS
                case (digit_count)
                    3'd1:    lcd_string = "MA MOI: *       ";
                    3'd2:    lcd_string = "MA MOI: **      ";
                    3'd3:    lcd_string = "MA MOI: ***     ";
                    3'd4:    lcd_string = "MA MOI: ****    ";
                    default: lcd_string = "NHAP MA MOI...  ";
                endcase
            end

            default: lcd_string = "HE THONG LOI    ";

        endcase
    end

endmodule