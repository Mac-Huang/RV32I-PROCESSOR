module child(input wire rst, input wire wen, input wire [31:0] wdata, output wire [31:0] y);
assign y = rst ? 32'd0 : (wen ? wdata : 32'd0);
endmodule
module tb;
reg rst,wen; reg [31:0] wdata; wire [31:0] y;
child c(.rst(rst),.wen(wen),.wdata(wdata),.y(y));
initial begin rst=1;wen=0;wdata=0; #10; rst=0; wdata=32'hA5A5_A5A5; wen=1; $display("imm y=%h", y); #0; $display("#0 y=%h", y); #1; $finish; end
endmodule
