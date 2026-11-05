# Pipelined RV32IM RISC-V Processor Core

5-stage pipelined version of the uRISC-V RV32IM core, compared with the original non-pipelined core
and a clock-gated low-power variant. Course project for BEVD301L ASIC Design, VIT Chennai.

Flow: Cadence Xcelium (simulation), Genus (synthesis), Innovus (place and route). 90 nm library, slow corner, clock 7.2 ns.

## Results (7.2 ns)

| Metric | Non-pipelined | Pipelined | Pipelined LP (clock-gated) |
|---|---|---|---|
| Cycles for the test program | 16,150 | 8,563 | 8,563 |
| Synthesis area (um^2) | 81,798 | 83,302 | 76,799 |
| Synthesis power, simulation activity (mW) | 3.56 | 4.03 | 3.25 |
| Energy per run (nJ) | 414 | 248 | 200 |
| Layout cell area (um^2) | 85,038 | 87,638 | 83,911 |
| Setup slack after layout (ns) | +0.039 | +0.006 | +0.034 |
| Hold slack after layout (ns) | +0.142 | +0.235 | +0.004 |

## Pipelined core

Stages IF, ID, EX, MEM, WB with MEM/WB-to-EX forwarding, register-file write-through bypass, a one-cycle load-use stall,
branch/jump/trap resolution in EX (one-cycle penalty), a multiply/divide stall and precise traps.
The ALU, branch, CSR, load/store and multiply/divide blocks are the original, unmodified uRISC-V modules.
See `PIPELINE_DESIGN.md`.

The low-power variant uses the same RTL. Clock gating is inserted by Genus (design name ending in `_lp`).

## Layout

- `rtl/nonpipelined/` original multi-cycle core
- `rtl/pipelined/` pipelined core (`riscv_core.v` is the rewritten top level)
- `tb/` testbench, memory models and the test program `test.elf` (10 self-checking tests)
- `scripts/` simulation, synthesis and place-and-route scripts (`sim.sh`, `syn.sh`, `pnr.sh`, `fix_setup.sh`, `fix_hold.sh`, `collect.sh`)
- `constraints/riscv.sdc` timing constraints
- `config.sh` paths, library and period settings (edit for your own setup)
- `HOW_TO_RUN.txt` step-by-step run instructions

## Verification

10/10 directed tests on all designs; 300 random programs compared with the original core (0 mismatches);
injected-bug checks (no forwarding, no load-use stall, no bypass, no flush) were each detected.

## Not included

The 90 nm library and LEF files are licensed and are not part of this repository. Set their paths in `config.sh`.

## Credit

Based on uRISC-V (ultraembedded, Apache 2.0): https://github.com/ultraembedded/core_uriscv

Authors: Rupaswathikaa S P, Sirichandana, Bhavana Sri Sanvi. Faculty: Dr. Shakthivel S M.
