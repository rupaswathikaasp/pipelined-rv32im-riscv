// Second top module. Counts cycles until the program reaches its final self-loop.
// Works for both designs (only uses top-level fetch port). Prints: PERF cycles=<N>
module perf_mon;
  parameter THRESH = 5000;
  integer cyc = 0;
  integer hits  [0:16383];
  integer first [0:16383];
  integer i, idx;
  reg started = 0;
  initial for (i=0;i<16384;i=i+1) begin hits[i]=0; first[i]=-1; end
  always @(posedge tb_top.clk) begin
    if (tb_top.rst) begin cyc = 0; started = 0; end
    else begin
      started = 1; cyc = cyc + 1;
      if (tb_top.mem_i_rd_w) begin
        idx = tb_top.mem_i_pc_w[15:2];
        if (first[idx] < 0) first[idx] = cyc;
        hits[idx] = hits[idx] + 1;
        if (hits[idx] >= THRESH) begin
          $display("PERF cycles=%0d halt_pc=%h", first[idx], tb_top.mem_i_pc_w);
          $finish;
        end
      end
    end
  end
  initial begin #50_000_000; $display("PERF TIMEOUT (no halt found)"); $finish; end
endmodule
