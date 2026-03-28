module t;
  reg [12:0] x;
  initial begin
    x = 13'b1_111111_1110_0;
    $display("x=%b x12=%b x11=%b", x, x[12], x[11]);
    $finish;
  end
endmodule
