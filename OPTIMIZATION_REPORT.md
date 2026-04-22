# RV32I CPI Optimization Report

## Summary

This implementation focuses on reducing stalls from instruction fetch misses,
cache conflict misses, and repeated taken-branch squashes while keeping the
existing `hart` memory and retire interfaces unchanged.

## Correctness Fix

- `rtl/decode.v` now reports unused retire source registers as `x0` with data
  `0`.
- This fixes the previous I-type/load/JAL/JALR retire metadata issue where
  `rs2` exposed raw instruction bits even when the instruction did not read
  `rs2`.

## Optimizations

### 1. Instruction Prefetcher

- `rtl/cache.v` has an optional `PREFETCH_EN` parameter.
- The instruction cache enables this parameter; the data cache leaves it off.
- After a demand read miss fills a 16-byte line, the cache opportunistically
  fetches the next sequential 16-byte line when it is not already resident.
- Demand requests and write-buffer drains remain higher priority than prefetch
  work. If demand fetch catches an in-progress prefetch line, the cache waits
  for that line instead of issuing a duplicate refill.

### 2. Increased Cache Associativity

- The cache is now 4-way set associative instead of 2-way set associative.
- It now uses 64 sets, 16-byte cache lines, a write-through policy, and an
  8-entry write buffer.
- Replacement is invalid-way-first, then per-set round-robin.

### 3. Improved Branch Predictor

- `rtl/hart.v` now uses a 128-entry direct-mapped BTB with 2-bit saturating
  counters.
- Fetch predicts taken when the BTB tag matches and the counter is in a taken
  state.
- When the BTB has no entry and the instruction is available from I-cache, IF
  statically predicts `jal` and backward conditional branches taken.
- When a cold I-cache miss returns a `jal` or backward branch that was not
  dynamically predicted, the fetch PC is redirected immediately from the miss
  response instead of waiting for EX.
- Predicted target metadata is carried through `IF/ID` and `ID/EX`.
- EX compares the predicted next PC with the architectural next PC and redirects
  only on mismatch, including wrong-target and false-taken predictions.

## CPI Results

Measured locally with `python tests/test_hart.py`. Reference CPI is the harness
reference value; after CPI is this implementation after the optimizations above.

| Test | Before CPI | After CPI |
| --- | ---: | ---: |
| `01add` | 4.12 | 3.49 |
| `02addi` | 4.05 | 3.44 |
| `06memory` | 4.17 | 3.26 |
| `exhaustive_nobranch` | 4.74 | 4.19 |
| `factorial_2` | 3.46 | 3.12 |
| `factorial_5` | 2.30 | 1.91 |
| `sort` | 1.60 | 1.32 |

## Local Sanity

- `python tests/test_hart.py`
- Result: all 25 grader-style tests passed locally.
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_tests.ps1 -Test all -KeepGoing`
- Result: all unit tests passed before the final predictor-size/static-redirect
  pass; the full grader-style run above was rerun after the final changes.
- CPI-producing local run target: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_tests.ps1 -Test hart_cpi`
- Current local `program.mem` result from `hart_cpi`: 422 cycles, 121 retired instructions, CPI 3.487603.
- Added advanced self-checking asm test: `tests/asm/advanced_tests/rv32i_instruction_sweep.asm`.
- Added grader-style asm/CPI runner: `python tests/test_hart.py` or `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_tests.ps1 -Test hart_grade`.
- The grader-style runner prints the `test_<name>` and `test_<name>_cpi` sections for the 21 basic tests plus `exhaustive_nobranch`, `factorial_2`, `factorial_5`, and `sort`; pass `--include-extra` to include `rv32i_instruction_sweep`.
- `tests/test_hart.py` now includes a built-in RV32I assembler fallback, so `RISCV_AS`/`RISCV_GCC` are optional for the provided tests.
