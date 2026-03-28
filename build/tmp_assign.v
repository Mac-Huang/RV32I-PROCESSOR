module m(input wire [31:0] a, output wire [31:0] y); assign y=a; endmodule
module tb; reg [31:0] a; wire [31:0] y; m u(.a(a),.y(y)); initial begin a=0; #10; a=32'hA5A5A5A5; $display("imm y=%h",y); #0; $display("#0 y=%h",y); #1;$finish; end endmodule
