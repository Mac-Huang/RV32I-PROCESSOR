module alu_control_unit (
  input  wire [2:0] AluOp,
  input  wire [2:0] Func3,          // corresponding to i_opsel
  input  wire [6:0] Func7,
  input  wire [6:0] opcode,
  output reg  [2:0] AluControl_opsel,
  output reg        AluControl_sub,
  output reg        AluControl_unsigned,
  output reg        AluControl_arith
);

    always @(*) begin
        AluControl_opsel    = 3'b000;
        AluControl_sub      = 1'b0;
        AluControl_unsigned = 1'b0;
        AluControl_arith    = 1'b0;

        casez (AluOp)
            3'b0?1: begin // Register Arithmetic & Immediate Arithmetic
                if (opcode == 7'b0110111 || opcode == 7'b0010111) begin
                    // LUI/AUIPC: force ADD
                    AluControl_opsel    = 3'b000;
                    AluControl_sub      = 1'b0;
                    AluControl_unsigned = 1'b0;
                    AluControl_arith    = 1'b0;
                end else begin
                    AluControl_opsel = Func3;
                    AluControl_sub = (Func3 == 3'b000) && Func7[5];
                    AluControl_unsigned = (Func3 == 3'b011);
                    AluControl_arith = (Func3 == 3'b101) && Func7[5];
                end
            end

            3'b0?0: begin // Load & Store
                // force ADD
                AluControl_opsel    = 3'b000;
                AluControl_sub      = 1'b0;
                AluControl_unsigned = 1'b0;
                AluControl_arith    = 1'b0;
            end

            3'b110: begin // Conditional Branch
                // force substraction
                AluControl_opsel    = 3'b000;
                AluControl_sub      = 1'b1;

                AluControl_unsigned = Func3[1];
                AluControl_arith    = 1'b0;
            end

            default: begin
                // fallback
                AluControl_opsel    = 3'b000;
                AluControl_sub      = 1'b0;
                AluControl_unsigned = 1'b0;
                AluControl_arith    = 1'b0;
            end
        endcase
    end

endmodule