# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

VHDL hardware accelerator for hyperdimensional computing (HDC) classification, targeting the Cologne Chip **GateMate** FPGA (GHDL → Yosys `synth_gatemate` → `nextpnr-himbaechel`) and a full **IHP SG13CMOS5L chip** (pad ring + bondpads) via LibreLane (`asic/`). FPGA sources are flat in the root; there is no Makefile or pin-constraint (`.ccf`) file. Git remote: `git@gitlab.rrze.fau.de:cs3/private/projects/passionate/hdc.git` (runs, logs and sim build output are ignored). Some comments are in German.

## Commands

Toolchain on PATH: `ghdl`, `yosys` (with the `ghdl` plugin), `nextpnr-himbaechel`, `nvc`. Run tool output in a scratch directory so `work-obj08.cf` / netlists don't litter the source dir.

```sh
S=/home/michael/Documents/Passionate/hdc
SRCS="$S/uart_rx.vhdl $S/uart_tx.vhdl $S/IdentityMemory.vhdl $S/ContinuousMemory.vhdl $S/AssociativeMemory.vhdl $S/ClassCounterRAM.vhdl $S/MajorityRAM.vhdl $S/Accelerator.vhdl $S/hdc_uart_loader.vhdl"

# Analyze + elaborate (syntax/type check). Dependency order matters: leaves first, tops last.
ghdl -a --std=08 $SRCS $S/hdc_word40_top.vhdl $S/hdc_word40_core_top.vhdl
ghdl -e --std=08 hdc_word40_top

# Synthesize for GateMate (files must come before `-e <top>` in the yosys ghdl command)
yosys -m ghdl -p "ghdl --std=08 $SRCS $S/hdc_word40_core_top.vhdl -e hdc_word40_core_top; synth_gatemate -top hdc_word40_core_top; stat"

# Override generics at synthesis time, e.g. -gG_D=2000 -gG_SUPPORT_TRAINING=false
yosys -m ghdl -p "ghdl --std=08 -gG_D=2000 $SRCS $S/hdc_word40_top.vhdl -e hdc_word40_top; synth_gatemate -top hdc_word40_top -vlog out.v"
```

Expect harmless `unhandled attribute "ram_style"` warnings; the `found RAM ...` notes confirm BRAM inference.

## Top-level entities

- `hdc_word40_top` — real design: `uart_rx`/`uart_tx` ↔ `hdc_uart_loader` (command FSM) ↔ `Accelerator`. Defaults D=10000, 10 MHz clock, 115200 baud. `led_o` = `done`.
- `hdc_word40_core_top` — accelerator only, driven by a free-running counter as synthetic stimulus. Used purely for resource/timing measurement (default D=1000); outputs are XOR-folded into `led_o` so nothing gets optimized away. Not functionally meaningful.

## Accelerator architecture (`Accelerator.vhdl`)

Generics: `D` (hypervector bits), `N` (features per sample, 32), `M` (quantization levels, 40), `K` (classes, ≤ 8 since `recognized_class` is 3 bits), `WORD_WIDTH` (must be 40 — `popcount_word` and the loader's 40-bit data path are hardcoded), `SUPPORT_TRAINING` (generates the counter RAM).

**Memories** — all single-port, synchronous, 1-cycle registered read, 16-bit word address. Each hypervector is stored as `CHUNKS_PER_VEC = ceil(D/40)` consecutive 40-bit words: vector `v`, chunk `c` lives at address `v*CHUNKS_PER_VEC + c`.
- IM (`IdentityMemory`, N vectors) — one random HV per feature position. `mem_sel="00"`.
- CM (`ContinuousMemory.vhdl`; note entity is spelled **`ContinousMemory`**) — M level HVs. `mem_sel="01"`.
- AM (`AssociativeMemory`, K vectors) — class prototypes. `mem_sel="10"`. Written externally (load mode) or internally by finalization.
- `ClassCounterRAM` — 11-bit signed counter per HV bit, for **one class only** (depth `CHUNKS_PER_VEC*40`). No address bounds check (to keep RAM inference); the others have sim-only asserts.
- `MajorityRAM` — the current sample's encoded HV (separate write/read address; never read and written in the same cycle, which the ASIC single-port mapping relies on).

**Main FSM flow:**
1. Features arrive via `feature_valid` into a 32-entry buffer; `features_ready` after N values, cleared on `start`.
2. Encoding (`S_ENC_WAIT`/`S_ENC_ACC`/`S_WRITE_MAJ`) — chunk-outer, feature-inner loop: for each chunk, XOR `IM[i]` with `CM[level(feature_i)]` for all N features, count per-bit, majority (`count >= N/2`) → `majority_ram[chunk]`. Level = `round(feature * (M-1) / 32768)`, clamped, so features are expected in Q15 range 0..32767.
3. Training (`train_mode=1`): `S_TRAIN_ACC` does ±1 on each counter bit (3-phase read/wait/write per bit, so ~3·D cycles).
4. Finalize (`train_mode=1` + `finalize_training` + `start`): `S_FINAL_WRITE` writes sign(counter) into AM row `label_in`, then `S_CLEAR_COUNTERS` zeroes the counter RAM.
5. Testing (`train_mode=0`): `S_COMPARE` computes Hamming distance (XOR + popcount) against every AM row, outputs argmin as `recognized_class`.

`done` pulses at the end of train, finalize, and test. Because only one counter block exists, **the host must train all samples of one label, then finalize that label, before moving to the next.**

`hv_length` is an input port but is currently unused: `ACTIVE_CHUNKS` is hardwired to `CHUNKS_PER_VEC` to avoid GHDL synthesis issues with integer arithmetic derived from a port.

## ASIC flow (`asic/`): full chip on IHP SG13CMOS5L

Top is `hdc_chip_top` (`asic/rtl/hdc_chip_top.vhdl`): sg13cmos5l IO pad ring + bondpads around `hdc_word40_top` (instance `i_core`). The flow is LibreLane's `Chip` flow with the `VHDLClassic` substitutions applied in `config.yaml` (`Yosys.Synthesis` → `Yosys.VHDLSynthesis`, lint/JSON-header/`Odb.SetPowerConnections`/EQY removed). Based on https://github.com/IHP-GmbH/ihp-sg13-librelane-template.

```sh
# Full run (runs land in asic/runs/<tag>)
cd asic && nix run /home/michael/Documents/Passionate/librelane -- --manual-pdk --pdk-root /opt/IHP-Open-PDK --pdk ihp-sg13cmos5l --run-tag <tag> config.yaml
# Stop early: --to Yosys.VHDLSynthesis, --to OpenROAD.GeneratePDN (pad ring + PDN take ~2 min)

# FPGA-memory vs. SRAM-macro equivalence sim of the Accelerator (GHDL, libs fpga/asic; ~25 s at D=10000)
asic/sim/run.sh            # or: asic/sim/run.sh -gG_D=2000

# Regenerate the bondpad (inside nix shell ~/Documents/doktor/nix-passionate#pyenv)
cd asic/ip/bondpad_70x70 && K=/opt/IHP-Open-PDK/ihp-sg13cmos5l/libs.tech/klayout && \
  KLAYOUT_PATH=$K KLAYOUT_HOME=$K klayout -n sg13cmos5l -zz -r gen_bondpad.py -rd pdk_root=/opt/IHP-Open-PDK
```

**Memories.** `asic/rtl/` holds ASIC-only architectures of the memory entities (**same entity names and ports** as the root files: swap file lists, never compile both into one library). They map onto IHP SRAM black boxes: `sg13_sram_macro` (name switch, BIST off, `A_DLY`=1; extended identifiers keep macro/pin case through GHDL) → `sram_array` (bank × column grid of one macro type) → `sram_w40` (40-bit = 2048x32 + 4096x8). Counters use 4096x16, MajorityRAM one 256x48: 20 macros at D=10000. `asic/sim/sram_models.vhdl` are hand-written sim models of the macros, never in `VHDL_FILES`.

**Floorplan** (`config.yaml`): die 4440×2350, core [365, 365, 4075, 1985]. Two manually placed SRAM rows (`MACROS.*.instances`), pins facing a ~280 µm logic channel. Instance names come from GHDL generate labels (`g_banks:1` is 1-based) under `i_core.`. Changing memory generics/D changes names and bank counts, so re-derive them from the synthesized netlist.

**Pads.** 23 pads: clk/rstn/rxd (`IOPadIn`), txd/led (`IOPadOut30mA`), 4× VDD, 4× VSS, IOVDD, IOVSS, and 8 spare `IOPadIn` (`spare*_pad`, outputs open). Things that are easy to break:
- All pad instance names end in `_pad`; `PAD_*` lists and `PDN_MACRO_CONNECTIONS` rely on it. VHDL is case-insensitive, so top ports are `pad_*` (not `*_PAD`).
- `rtl/pad_keep.v` (via `EXTRA_VERILOG_MODELS`) redefines the power pads and `IOPadIn` as `(* keep *)` black boxes. GHDL drops VHDL `keep` attributes, and Yosys would otherwise delete port-less or unused-output pads.
- No `Odb.SetPowerConnections` in the VHDL flow, so pad power pins are tied to VDD/VSS/IOVDD/IOVSS through `PDN_MACRO_CONNECTIONS` (pin patterns anchored, `^vdd$`, so `vdd` doesn't match `iovdd`). IO fillers/corners get their nets by abutment.
- The spare `IOPadIn` cells exist for the KLayout antenna check: each `IOPadIn` has a vdd-tied gate, and the IO ring's vdd rails (continuous around the die) give that net ratio ≈ rail area / total such gate area. With this die it needs ≥ 10 `IOPadIn` to stay below `Ant.e` 20000. Shrinking the die or removing spare inputs brings the errors back.
- The clock must match the UART divider: `G_CLK_FREQ_HZ` default in `hdc_chip_top` is 50 MHz = `CLOCK_PERIOD: 20`.

**Bondpad** (`asic/ip/bondpad_70x70/`) is generated by the PDK's `bondpad.py` through `gen_bondpad.py`, which works around three bugs in it: string `diameter` crashes the LEF writer; the GDS is centred on (0,0) while the LEF starts at (0,0); LEF `CLASS COVER BUMP` is rejected by OpenROAD's `place_bondpad` (needs `COVER`). Name `bondpad_70x70` and offsets come from the PDK IO config.

**PDN.** `asic/pdn_cfg.tcl` is the template's `pdn_cfg.tcl` unchanged except the SRAM section (one macro grid selecting all SRAM cells by master, Metal4↔TopMetal1). pdngen's `-connect_to_pads` only creates core-ring↔IO-ring straps on the **west/east** sides, mostly into IO filler cells (pads collide with the TopMetal1 core stripes). North/south get none; the IHP template render shows the same, so it is treated as a PDK limitation. Core power pairs 2/3 therefore sit on west/east. A VDD pad never gets its own strap (its TopMetal1 `vdd` shape makes pdngen reject it); it feeds the core via the IO ring rail. When verifying this, count straps into *all* IO-ring cells per side; LibreLane's grid-error reports / PSM-0040 don't detect missing pad connections.

**Disabled steps:** Magic DRC, Magic stream-out + KLayout XOR, Magic SPICE extraction, IllegalOverlap, and LVS (Netgen and checker): slow and inaccurate for cmos5l. KLayout DRC, antenna, density, seal ring and fill run as in the `Chip` flow.

**Fill / signoff runtime.** The PDK `filler.py` runs flat and was killed after reaching ~30 GB (it flattens all SRAM internals). `KLAYOUT_FILLER_SCRIPT` points to `asic/drc/filler/filler_deep.py`, which runs copies of the PDK fill macros with `deep` prepended (fill cells land in the top cell only): ~1.7 GB but **~4.5 h**. Afterwards density takes ~8 min (all layers in range) and KLayout DRC ~1.5 h at ~10 GB peak (0 violations on chip2, chip3, chip5 and chip8). A full run takes roughly 8 h; to iterate on PnR, stop with `--to OpenROAD.STAPostPNR` (~1.5 h). Don't run two full flows at once on this 32 GB machine.

**Antenna.**
- Signoff uses `asic/drc/antenna_cmos5l_pr990.drc`: the PDK deck with IHP-Open-PDK PR #990 ported to the 5-metal stack (`has_diode` evaluated per layer with staged connectivity). The stock deck misses violations where diffusion only joins a net at Metal4. The deck needs its rule JSONs via `KLAYOUT_ANTENNA_OPTIONS`; these are absolute `/opt/IHP-Open-PDK` paths because `pdk_dir::` expands to a list there.
- OpenROAD's antenna checker counts only routed wire area: it ignores the pins' own metal and never reads `ANTENNAPARTIALMETALAREA` (checked in source and by test). KLayout counts both, so OpenROAD-clean nets end slightly over 200 in KLayout. The stdcell LEF is consistent (pin shapes cover all input Metal1 except `RESET_B`, which has the partial attribute). The gap is at most ~4 of ratio (`sdfbbp_1/SET_B`), so `TECH_LEFS` points to `asic/lef/sg13cmos5l_tech_ant195.lef`: the PDK tech LEF with metal `ANTENNACUMAREARATIO` (and the PWL start points) lowered from 200 to 195. SRAM pins carry much larger partial areas (up to ~69 of ratio on `A_ADDR`), so the margin does not cover them; they rely on ECO diodes instead. LibreLane's post-DRT loop only starts when `check_antennas` finds a hard violation, so `-ratio_margin` alone doesn't help near-limit nets.
- `INSERT_ECO_DIODES` puts an `sg13cmos5l_antennanp` on every functional SRAM input (clock, address, data, enables; 747 entries). Each one sits at the pin's x, 12 µm outside the pin edge: pin top + 12 µm for the bottom row (R180), pin bottom − 12 µm for R0 macros. The main list came from a one-off script that is not in the repo; the 20 `A_CLK` entries were added later with the same rule, from the pin boxes in the routed odb. **If macro placement, orientation or memory generics change, the list must be regenerated.**
- GRT/DRT antenna repair use margin 30 % and 5 iterations. The post-DRT repair loop in `drt.tcl` takes its margin from `GRT_ANTENNA_REPAIR_MARGIN`; `DRT_ANTENNA_REPAIR_MARGIN` is unused.
- `Odb.InsertECODiodes` runs right after `OpenROAD.CheckAntennas` (post-GRT), i.e. *before* `RepairDesignPostGRT`; inserted later, the diode load was invisible to repair.

**Timing / repair.** `RUN_POST_GRT_DESIGN_REPAIR` and `RUN_POST_GRT_RESIZER_TIMING` are enabled (off by default). The PDK only flags timing in `*typ*` corners (`TIMING_VIOLATION_CORNERS`); the slow corner is reported but not checked. Remaining post-route max-slew violations sit mostly on the SRAM address nets (`im/cim.addr[*]`), each driven by a single `o21ai_1` across a whole SRAM row plus diodes. Post-GRT `repair_design` finds them but inserts 0 buffers (cause unknown). Global routing sometimes sends a clock net around the bottom SRAM row (chip6: +1.5 mm wire, +0.33 ns skew, fast-corner hold −0.2 ns). The detour is often only created in the incremental reroute of `ResizerTimingPostGRT`, after pre-route hold repair has run, so `PL_/GRT_RESIZER_HOLD_SLACK_MARGIN` are raised to 0.3 ns. Hold is checked in all corners (`HOLD_VIOLATION_CORNERS ['*']`). Max-fanout "violations" on `clkbuf_leaf_*` are CTS leaf clusters (~20 sinks). STA `checks.rpt` order is slew → fanout → cap; parse by section header.

**Functional caveat:** SRAM contents are undefined at power-up, including the class counters, which the design only clears *after* a finalize. On the ASIC the host must issue one dummy finalize (`M 1`, `X`) after reset before training.

## UART protocol (`hdc_uart_loader.vhdl`)

8N1, all multi-byte fields little-endian. Most commands reply `'K'` (0x4B); unknown command replies `'E'` (0x45). On every rising edge of `done` the loader sends one byte `0x00..0x07` = `recognized_class` (sent only when the FSM is back in `WAIT_CMD`). Host must therefore distinguish ack bytes from result bytes.

| Cmd | Payload | Effect |
|---|---|---|
| `I` / `C` / `A` | addr(2) + data(5) | Write 40-bit word to IM / CM / AM |
| `R` | sel(`I`/`C`/else→AM) + addr(2) | Returns 5 data bytes (no `K`) |
| `F` | value(4) | Push one feature; after the 32nd, auto-pulses `start` |
| `M` | byte (bit 0) | `train_mode` |
| `L` | byte (bits 2..0) | `label` |
| `X` | — | `finalize` + `start` (requires `train_mode=1`) |
| `S` | — | Force `start` |

The loader's feature counter is hardcoded to 32, so N must stay 32 when using the UART top.
