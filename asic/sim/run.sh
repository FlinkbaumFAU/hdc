#!/bin/sh
# Equivalence simulation: Accelerator with FPGA memories vs. SG13 SRAM-macro memories.
# Usage: ./run.sh [extra ghdl -r args, e.g. -gG_D=2000]
set -e
cd "$(dirname "$0")"
R=../../..
A=../../rtl
mkdir -p build && cd build
G="ghdl -a --std=08 -frelaxed"
$G --work=fpga $R/IdentityMemory.vhdl $R/ContinuousMemory.vhdl $R/AssociativeMemory.vhdl \
   $R/ClassCounterRAM.vhdl $R/MajorityRAM.vhdl $R/Accelerator.vhdl
$G --work=asic ../sram_models.vhdl $A/sg13_sram_macro.vhdl $A/sram_array.vhdl $A/sram_w40.vhdl \
   $A/IdentityMemory.vhdl $A/ContinuousMemory.vhdl $A/AssociativeMemory.vhdl \
   $A/ClassCounterRAM.vhdl $A/MajorityRAM.vhdl $R/Accelerator.vhdl
$G ../tb_mem_equiv.vhdl
ghdl -e --std=08 -frelaxed tb_mem_equiv
ghdl -r --std=08 tb_mem_equiv --ieee-asserts=disable-at-0 "$@"
