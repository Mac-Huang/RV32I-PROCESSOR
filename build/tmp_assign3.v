module m(input wire wen, input wire [31:0] wdata, output wire [31:0] y); assign y = wen ? wdata : 32'd0; endmodule
module tb; reg wen; reg [31:0] wdata; wire [31:0] y; m u(.wen(wen),.wdata(wdata),.y(y)); initial begin wen=0; wdata=0; #9; wdata=32'hA5A5A5A5; #1; wen=1; $display("imm y=%h",y); #0; $display("#0 y=%h",y); #1;$finish; end endmodule
