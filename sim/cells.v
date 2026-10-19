// Behavioural models of ONLY the 9 standard cells used by counter.test_netlist.v.
// Written from the cell functions so the scan netlist can be simulated in
// open-source tools (Icarus / EDA Playground) without the proprietary GPDK045 library.

// Mux-scan D flip-flop with active-low async reset.
//   SE=0 -> Q <= D  (functional / capture)
//   SE=1 -> Q <= SI (scan shift)
module SDFFRHQX1(Q, D, SE, SI, RN, CK);
  input D, SE, SI, RN, CK;
  output reg Q;
  always @(posedge CK or negedge RN)
    if (!RN) Q <= 1'b0;
    else     Q <= SE ? SI : D;
endmodule

module INVX1   (Y, A);          input A;       output Y; assign Y = ~A;            endmodule
module AND2XL  (Y, A, B);       input A, B;    output Y; assign Y = A & B;         endmodule
module NAND2X1 (Y, A, B);       input A, B;    output Y; assign Y = ~(A & B);      endmodule
module XNOR2X1 (Y, A, B);       input A, B;    output Y; assign Y = ~(A ^ B);      endmodule
module NOR2BX1 (Y, AN, B);      input AN, B;   output Y; assign Y = ~(~AN | B);    endmodule
module OA21X1  (Y, A0, A1, B0); input A0,A1,B0; output Y; assign Y = (A0 | A1) & B0; endmodule
// AOI2BB1: Y = ~((~A0N & ~A1N) | B0)
module AOI2BB1X1(Y, A0N, A1N, B0); input A0N,A1N,B0; output Y; assign Y = ~((~A0N & ~A1N) | B0); endmodule
module AOI2BB1XL(Y, A0N, A1N, B0); input A0N,A1N,B0; output Y; assign Y = ~((~A0N & ~A1N) | B0); endmodule
