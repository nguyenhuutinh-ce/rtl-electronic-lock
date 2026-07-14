module password_manager (
	input clk, reset_n,
   input [3:0] key_in,      // Mã phím từ bàn phím
   input key_pressed,       // Xung báo có phím nhấn
   input clr_buffer,        // Xóa đệm khi về S_IDLE hoặc sai mã
   input load_new_pass,     // Cho phép ghi đè mã mới
   output reg match,        // Kết quả so sánh
   output reg [2:0] count   // Số chữ số đã nhập (0-4)
);
   reg [15:0] saved_pass;   // Mật mã gốc (1234)
   reg [15:0] buffer;       // Bộ đệm nhập liệu
   // cập nhật mật mã gốc 
   always @(posedge clk or negedge reset_n) 
		if (!reset_n) 
			saved_pass <= 16'h1234; 
      else 
			if (load_new_pass)
				saved_pass <= buffer; 
   // cập nhật bộ đệm 
   always @(posedge clk or negedge reset_n) begin
		if (!reset_n) begin
			buffer <= 16'h0; count <= 3'd0;
		end 
		else 
			if (clr_buffer) begin
				buffer <= 16'h0; count <= 3'd0;
			end 
			else 
				if (key_pressed && count < 3'd4) begin
					// Dịch chuyển bit để nhận phím mới
					buffer <= {buffer[11:0], key_in}; 
					count <= count + 3'd1;
				end
	end
	always @(*) begin
		match = (buffer == saved_pass) && (count == 3'd4);
	end
endmodule
