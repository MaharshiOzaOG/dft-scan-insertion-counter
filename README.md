# Scan Insertion (DFT) on an 8-bit Counter: Cadence Genus + Modus

The full Design-for-Test flow on a small design: RTL, then synthesis with **mux-scan insertion** in Cadence Genus, then an ATPG-ready test netlist and Modus scripts. The repo also includes an **open-source simulation** that proves the scan chain works.

## 1. The problem

When a chip comes back from the fab, some dies have manufacturing defects: shorts, opens, or a node stuck at 0 or 1. Each die has to be tested in seconds. The tester can only drive the **primary inputs** and watch the **primary outputs**.

Flip-flops make this hard. To test the logic between two registers you first have to **put the registers into a specific state** (controllability) and then **read the result back** (observability). With functional inputs alone, that can take thousands of cycles, or it may be impossible.

**Lab objective (Lab 4-1):** Synthesize an 8-bit counter in Genus with DFT so that every flip-flop becomes a scan flop on one scan chain. Then generate the files needed for ATPG (Modus) and pattern simulation.

## 2. The solution: mux-based scan

Every normal DFF is swapped for a **scan flop** (`SDFFRHQX1`), which is a DFF with a 2:1 mux on its input:

```
          SE
          |
 D  ---->|0\
         |  |---> DFF ---> Q
 SI ---->|1/
```

| SE | Mode | What happens |
|----|------|--------------|
| 1 | **Shift** | The flops form one long shift register: `scan_in → count[0] → … → count[7] → scan_out` |
| 0 | **Capture / functional** | Normal counter behaviour: `D` is the combinational "+1" logic |

**How a test pattern runs:**
1. **Load:** with SE=1, shift 8 bits in. Any state can now be set directly.
2. **Capture:** with SE=0, apply 1 clock. The logic computes, and the flops capture the result.
3. **Unload:** with SE=1, shift 8 bits out through `scan_out` (while the next pattern shifts in).

A sequential testing problem becomes a **combinational** one, so an ATPG tool can generate patterns automatically and reach close to 100% stuck-at fault coverage.

## 3. The flow

```
rtl/counter.v ──► Genus ──► scan netlist ──► write_dft_atpg ──► Modus ATPG ──► patterns ──► Xcelium sim
                 (synthesis/genus_dft_script.tcl)                (test_scripts/)
```

| Step | Command | Why |
|------|---------|-----|
| Read libs, RTL, SDC | `read_libs`, `read_hdl`, `elaborate`, `read_sdc` | Normal synthesis setup (10 ns clock) |
| Scan style | `set_db dft_scan_style muxed_scan` | Use mux-D scan flops |
| Name prefix | `set_db dft_prefix dft_` | Prefix for inserted DFT logic and ports |
| Test signal | `define_shift_enable -name SE -active high -create_port SE` | Create the SE port (newer Genus: `define_test_signal -function shift_enable …`) |
| DRC | `check_dft_rules` | Checks each flop is scannable: clock and reset must be controllable from pins. All 8 pass |
| Synthesize | `syn_generic`, `syn_map`, `syn_opt` | Flops get mapped straight to scan flops |
| Chain setup | `dft_min_number_of_scan_chains 1`, `define_scan_chain -sdi scan_in -sdo scan_out -create_ports` | One chain plus its ports |
| Stitch | `connect_scan_chains -auto_create_chains` | Wires each `Q` to the next flop's `SI` |
| Re-opt | `syn_opt -incremental` | Fixes timing after stitching |
| Outputs | `write_hdl/sdc/sdf/scandef`, `write_dft_atpg` | Netlist, constraints, delays, chain description (for P&R reordering), Modus scripts |

### Generated ATPG files (`test_scripts/`)
- **`counter.test_netlist.v`**: the scan netlist. Look for `SDFFRHQX1` with `.SI(count[n-1])` and `.SE(SE)`, and `assign scan_out = count[7]`.
- **`counter.FULLSCAN.pinassign`**: tells Modus what each pin does in test mode:
  - `rst +SC`: scan-constant, held at 1 (inactive) during test
  - `SE +SE`: shift enable, active high
  - `clk -ES`: clock, with the off-state low
  - `scan_in SI0` / `scan_out SO0`: chain 0 input and output
- **`runmodus.atpg.tcl`**: `build_model` → `build_testmode` → `verify_test_structures` → `build_faultmodel` → `create_logic_tests` → `write_vectors` → `commit_tests`
- **`run_fullscan_sim` / `_sdf`**: Xcelium simulation of the patterns, with zero delay or SDF back-annotation

## 4. Verifying without Cadence tools (`sim/`)

Genus and Modus are licensed tools. To show that the scan netlist really works, `sim/tb_scan_counter.v` drives the **actual Genus netlist** through the same load, capture and unload sequence that an ATPG pattern uses:

| Check | Shows |
|-------|-------|
| reset → `00` | async reset works |
| 5 clocks with SE=0 → `05` | functional behaviour is unchanged |
| shift in `A5` | **controllability**: any state can be loaded |
| 1 capture clock → `A6` | logic tested in a single cycle |
| shift out → `A6` on `scan_out` | **observability** |
| load `FF`, capture → `00` | whole carry chain exercised |

`sim/cells.v` contains clean-room behavioural models of the 9 cells the netlist uses. The GPDK045 library is proprietary and is not included.

**Run it:**
```bash
cd sim
iverilog -o sim tb_scan_counter.v ../test_scripts/counter.test_netlist.v cells.v && vvp sim
```
**EDA Playground:** paste `tb_scan_counter.v` into the testbench pane. In the design pane, paste `counter.test_netlist.v` followed by `cells.v`. Select *Icarus Verilog*, tick *Open EPWave* and run.

### Simulation results (`logs/`)
```
PASS reset: count = 00
PASS functional count x5: count = 05
PASS scan load A5: count = a5
PASS capture A5+1: count = a6
PASS scan unload: captured response A6 seen on scan_out
PASS capture FF+1 wraps: count = 00
*** ALL TESTS PASSED ***
```
`logs/scan_counter_dump.vcd` is the waveform. Open it in GTKWave or EPWave and look at `SE`, `scan_in`, `scan_out` and `count`.

## 5. Key concepts

- **Stuck-at fault model:** a defect is modelled as a net stuck at 0 or 1. A test detects the fault if the faulty and good circuits give different outputs.
- **Controllability / observability:** how easily a node can be set from the inputs, or seen at the outputs. Scan makes every flop directly controllable and observable.
- **Mux-D scan cell:** a DFF with a 2:1 mux. `SE` selects between functional `D` and scan `SI`.
- **Scan test protocol:** load (shift), capture (1 functional clock), unload (shift, overlapped with the next load).
- **DFT rules:** test clocks and async set/reset must be controllable from primary inputs, otherwise the flop can't be scanned. That is why `rst` is held inactive (`+SC`) in test mode.
- **ATPG:** with scan, the tool only has to solve the combinational logic between flops to generate patterns and measure fault coverage.

## 6. Interview Q&A

**Q: Scan vs ATPG?**
Scan is a *hardware* change that makes the design testable. ATPG is the *software* that generates the test patterns for it.

**Q: Cost of scan?**
Area (one mux per flop), an extra mux delay on the functional `D` path, routing for the chain, and extra pins (`SE`, `SI`, `SO`). Test power is also higher, because shifting toggles many flops at once.

**Q: Why more than one chain?**
Test time is set by the longest chain. N balanced chains cut shift cycles by about N, and scan compression (for example Modus OPCG/compression) goes further.

**Q: Why must reset be inactive during shift?**
An async reset firing mid-shift would wipe the chain contents, so the loaded pattern would be lost.

**Q: Stuck-at vs transition faults?**
Stuck-at faults are static logic faults, tested at slow speed. Transition faults are slow-to-rise or slow-to-fall delay defects, tested at speed with launch-on-shift or launch-on-capture.

**Q: Why the ScanDEF output?**
Place-and-route reorders the chain to cut wiring. ScanDEF tells the P&R tool which flops belong to which chain and which can be reordered.

## Repo layout
```
rtl/            counter.v (original RTL)
constraints/    constraints_top.sdc
synthesis/      genus_script.tcl (plain synthesis), genus_dft_script.tcl (with scan)
test_scripts/   Genus-generated ATPG netlist, pinassign, Modus & Xcelium scripts
sim/            open-source testbench + cell models
```

## Notes
- The counter RTL uses blocking assignments (`=`) in a clocked block. Non-blocking (`<=`) is the correct style, though the result here is the same.
- Scan only replaces flops and stitches them together. ATPG then generates the actual stuck-at patterns. With 8 flops and one chain, each pattern takes 8 shift cycles plus 1 capture cycle.

*Based on the Cadence "Design for Test" training Lab 4-1. Cadence libraries and lab material are not redistributed here.*
