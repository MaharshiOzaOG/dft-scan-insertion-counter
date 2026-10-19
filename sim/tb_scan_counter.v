`timescale 1ns/1ps
// Self-checking testbench for the scan-inserted 8-bit counter.
// Mimics what Modus ATPG patterns do: scan-load -> capture -> scan-unload.
//
// Chain order (from netlist): scan_in -> count[0] -> count[1] -> ... -> count[7] -> scan_out
module tb_scan_counter;
  reg clk = 0, rst = 0, SE = 0, scan_in = 0;
  wire [7:0] count;
  wire scan_out;
  integer errors = 0, i;
  reg [7:0] unloaded;

  counter dut(.clk(clk), .rst(rst), .count(count), .SE(SE), .scan_in(scan_in), .scan_out(scan_out));

  always #5 clk = ~clk;   // 10 ns period, matches constraints_top.sdc

  task check(input [7:0] exp, input [255:0] msg);
    if (count !== exp) begin errors = errors + 1; $display("FAIL %0s: got %h exp %h", msg, count, exp); end
    else               $display("PASS %0s: count = %h", msg, count);
  endtask

  // Shift 8 bits in (MSB first, so it ends in count[7]) while shifting old contents out.
  task scan_shift(input [7:0] load, output [7:0] unload);
    begin
      SE = 1;
      for (i = 7; i >= 0; i = i - 1) begin
        scan_in = load[i];
        @(negedge clk); unload[i] = scan_out;   // observe before the next shift edge
        @(posedge clk); #1;
      end
      SE = 0;
    end
  endtask

  initial begin
    $dumpfile("dump.vcd"); $dumpvars(0, tb_scan_counter);

    // 1) Reset
    #12 check(8'h00, "reset");
    rst = 1;

    // 2) Functional mode (SE=0): it is still a counter
    repeat (5) @(posedge clk); #1;
    check(8'h05, "functional count x5");

    // 3) Scan load an arbitrary state - controllability
    scan_shift(8'hA5, unloaded);
    check(8'hA5, "scan load A5");

    // 4) Capture: one functional clock -> logic computes A5+1
    @(posedge clk); #1;
    check(8'hA6, "capture A5+1");

    // 5) Scan unload while loading next pattern - observability
    scan_shift(8'hFF, unloaded);
    if (unloaded !== 8'hA6) begin errors = errors + 1; $display("FAIL unload: got %h exp A6", unloaded); end
    else $display("PASS scan unload: captured response A6 seen on scan_out");

    // 6) Wrap-around test FF -> 00 (exercises the whole carry chain)
    @(posedge clk); #1;
    check(8'h00, "capture FF+1 wraps");

    if (errors == 0) $display("\n*** ALL TESTS PASSED ***");
    else             $display("\n*** %0d TEST(S) FAILED ***", errors);
    $finish;
  end
endmodule
