module child(input wire a, output wire y); assign y = a; endmodule
module tb;
reg a; wire y;
child c(.a(a),.y(y));
task check; input got; begin #1; $display("got=%b", got); end endtask
initial begin a=0; #10; a=1; check(y); #10; $finish; end
endmodule
