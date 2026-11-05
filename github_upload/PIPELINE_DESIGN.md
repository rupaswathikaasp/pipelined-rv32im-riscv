# 5-stage pipelined uriscv (RV32IM + Zicsr)

Built from the original multi-cycle uriscv (ultraembedded/core_uriscv). Same ports and
parameters; the original testbench runs unchanged. uriscv_alu/branch/lsu/csr/muldiv are the
original, unmodified modules; only riscv_core.v (the top level) was rewritten.

| Stage | What happens |
|---|---|
| IF  | PC sent to the instruction memory (1-cycle synchronous read). The memory output register acts as the IF/ID register. |
| ID  | Decode, register-file read (with write-back bypass), load-use hazard detection |
| EX  | ALU, forwarding muxes, branch/jump resolve, CSR, MUL/DIV, data-memory request |
| MEM | Load data returns; byte/half alignment and sign extension |
| WB  | Register-file write |

## Hazard handling
| Hazard | Solution | Cost |
|---|---|---|
| ALU result needed by next instruction | forward MEM -> EX | 0 cycles |
| Result needed 2 instructions later | forward WB -> EX | 0 cycles |
| Result needed 3 instructions later | register-file write-through bypass in ID | 0 cycles |
| Load followed by dependent instruction | stall IF/ID one cycle | 1 cycle |
| Taken branch / JAL / JALR / trap / MRET | resolved in EX, wrong-path instruction flushed | 1 cycle |
| MUL / DIV (multi-cycle unit) | whole pipeline stalls until result ready | 2 / ~34 cycles |

Branches are predicted not-taken (no predictor, to keep area and power low).

## Assumption
Instruction and data memories accept every request and answer exactly one cycle later
(true for the supplied tcm_mem testbench memory).

## Results (supplied test.elf, all 10 tests pass)
| | Original (multi-cycle) | Pipelined |
|---|---|---|
| Cycles to finish | 16150 | 8563 |
| Speed-up | 1.00x | 1.89x |

## Verification done
* test.elf: identical output, all 10 tests pass.
* 300 random programs (200 instructions each: ALU, shifts, MUL/DIV/REM, loads/stores of all
  sizes, forward branches, JAL, JALR, back-to-back dependencies). Final register file and
  data memory compared against the original core: 0 mismatches.
* Sanity check of the test itself: 5 deliberately injected bugs (no forwarding, no load-use
  stall, no bypass, no flush) were each detected.
