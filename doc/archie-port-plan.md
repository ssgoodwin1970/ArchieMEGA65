# ArchieMEGA65 port plan

Target: MEGA65 R3 (`CORE/CORE-R3.xpr`). Framework: MiSTer2MEGA65 V2.0.1.
Core: `CORE/Archie_MiSTer` (git submodule of MiSTer-devel/Archie_MiSTer).

## Intel-only parts to replace

| File | Intel part | Xilinx replacement |
|---|---|---|
| `rtl/pll.v`, `rtl/pll/*` | `altera_pll` (50 MHz in -> 126 MHz mem, 42 MHz CPU) | MMCME2_ADV in `CORE/vhdl/clk.vhd` (100 MHz in) |
| `rtl/video_pll.v`, `video_pll_profile.v`, `pll_cfg` in `Archie.sv` | `altera_pll` + live reconfiguration (VIDC pixel clock families: 24 / 25.175 / 36 MHz, 96 MHz for mode 23) | Fixed MMCM outputs + BUFGMUX switch, or MMCM DRP reconfiguration |
| `rtl/sdram.v` | `altddio_out` + SDRAM controller | Drop. Bridge the Wishbone RAM bus to M2M HyperRAM (Avalon) |
| `rtl/bram.vhd` | `altsyncram` | Inferred dual-port BRAM |
| `rtl/amber/sram_byte_en.v`, `sram_line_en.v` | `altsyncram` (CPU cache) | Inferred BRAM with byte enables |
| `Archie.sv` `dpram_dif ... cmos.mif` | MiSTer `sys` dual-port RAM with `.mif` init | Inferred BRAM, init from `.hex`/`.mem` |
| `vidc_async_fifo.v`, `vidc_command_fifo.v`, `archimedes_top.v` | `altera_attribute` synchroniser hints | Harmless in Vivado; add `ASYNC_REG` attributes |

Everything else (Amber CPU, MEMC, IOC, VIDC, FDC 1772, IDE) is plain Verilog/SystemVerilog.

## MiSTer ARM/Linux services to replace

| MiSTer service | Where | M2M replacement |
|---|---|---|
| Keyboard (ARM emulates Archimedes keyboard controller over `hps_ext`, cmds 0x04/0x05) | `rtl/hps_ext.v` | New FPGA keyboard controller: MEGA65 matrix -> Archimedes KART protocol |
| IDE hard disks (ARM-side, cmds 0x61-0x63) | `rtl/hps_ext.v`, `ide.v` | Phase 2: QNICE-side IDE handler or vdrive-based sector access |
| Floppy `.adf` (819200 bytes), 2 drives | `sd_lba` / `sd_rd` via `hps_io` | M2M virtual drives (`vdrives.vhd`), `C_VDNUM = 2` |
| RISC OS ROM load (`riscos.rom`, ioctl index 0) | `ioctl_*` | M2M CRTROM loader, mandatory ROM at `/archie/riscos.rom` |
| CMOS load/save (`cmos.dat`, ioctl index 3) | `ioctl_*`, `cmos_cnt` | CRTROM loader + save-on-change via QNICE |
| RTC from Linux | `hps_io` RTC | `main_rtc_i` from the MEGA65 RTC |
| Mouse (PS/2 via ARM) | `hps_io` | MEGA65 1351 mouse port -> quadrature |
| OSD menu (`CONF_STR`) | `Archie.sv` | `CORE/vhdl/config.vhd` |
| Video scaling / HDMI | MiSTer `sys` | M2M `av_pipeline` + ascal |

## Phases

1. Skeleton + clocks + inferred RAMs. First Vivado build (expect errors).
2. HyperRAM bridge + ROM loader. Goal: RISC OS boots to the desktop, no keyboard.
3. Keyboard + mouse. Goal: usable desktop.
4. Floppy drives. Goal: games load from `.adf`.
5. CMOS save, RTC, menu polish.
6. Hard disks (`.hdf`).
7. Release `.cor` for R3.

## SD card layout (planned)

```
/archie/riscos.rom    (your own ROM, not in this repo)
/archie/cmos.dat
/archie/*.adf
```

## Design decisions

### Clocks (done: `CORE/vhdl/clk.vhd`)
One MMCM, 100 MHz in, /5 then x42 = 840 MHz VCO:
- 42 MHz system clock (`CLKOUT1`, /20), exactly the MiSTer `CLKSYS`.
- 96 MHz video clock (`CLKOUT0`, /8.75; fractional dividers must be multiples of 0.125).

The MiSTer core changes its video PLL per VIDC mode (24 / 25.175 / 36 MHz families, 96 MHz for mode 23).
Instead we run one fixed 96 MHz video clock and make each pixel rate with fractional clock
enables. Archie_MiSTer already has this logic (`cepix_60` / `vratio` in `Archie.sv`), so no
live PLL reconfiguration is needed. The M2M scaler (ascal) samples on the clock enable, so
the small pixel jitter does not matter on HDMI.

### Memory budget (MEGA65 R3: 8 MB HyperRAM, no SDRAM)
The MiSTer core uses RAM at 0-4 MB and loads the RISC OS ROM at 4 MB (up to 2 MB), 6 MB in all.
M2M reserves the first 4 MB of HyperRAM for its video scaler buffer (`C_HMAP_M2M`).

First version: **2 MB Archimedes RAM + 2 MB ROM** in the core's 4 MB window (A3000-class,
enough for RISC OS 3 and most games). RAM addresses above 2 MB alias, which is how real
machines with less RAM behave.

Later: if the scaler fits in 2 MB (input resolution up to 800x600, i.e. no mode 23 hi-res mono),
the core window grows to 6 MB and we go to the full 4 MB of RAM.

## Status

- [x] Clocks (42 / 96 MHz) - builds on R3.
- [x] Phase 1/2 wiring: `CORE/rtl/archie_main.v` replaces `Archie.sv`:
  - Wishbone -> 32-bit Avalon bridge that mimics `sdram.v` (4-word wrap bursts on reads).
  - HyperRAM path in `mega65.vhd`: `avm_fifo` (42 -> 100 MHz) + `avm_decrease` (32 -> 16 bit),
    window `C_HMAP_ARCHIE` = 4 MB.
  - RISC OS ROM: framework auto-loads `/archie/riscos.rom` into QNICE device `C_DEV_ARCHIE_ROM`;
    bytes cross clock domains via `qnice2hyperram` + `avm_fifo` and are packed into 32-bit words.
  - Intel RAMs replaced by `CORE/rtl/xilinx_rams.v`; CMOS defaults in `CORE/rtl/archie_cmos.mem`.
  - Video: fixed 96 MHz with fractional pixel enables; h/v blank derived from DE.
  - Simulation smoke test: `CORE/sim/run_tb.sh` (needs iverilog) - CPU runs code from ROM and
    reads/writes RAM through the bridge.
- [ ] Keyboard controller (phase 3) - keyboard input is tied off for now.
- [ ] Floppy, CMOS save, RTC, hard disks.

Known follow-ups:
- `podule_ide.sv` loads `rtl/riscdevide_rom.hex` with a Quartus-relative path (IDE ROM; phase 6).
- `fdc1772.sv` has `always begin` with no event list; fine in Quartus, check Vivado's view.

Core changes (kept on branch `mega65` of ssgoodwin1970/Archie_MiSTer):
- `rtl/fdc/fdc1772.sv`: `fdc1772_dpram` rewritten as a 16-bit true dual port RAM with byte
  write on port B. The mixed-width original became 8192 multiply-driven flip-flops in Vivado.

### First hardware test (R3)
RISC OS boots (mouse pointer drawn correctly), but the screen image is mostly noise with the
desktop faintly visible. Likely cause: HyperRAM round trips too slow for continuous video DMA.
Fix: 4-line x 64-byte read cache in the bridge (write-through, coherent), one 16-word HyperRAM
burst per line.
Second test: no change, noise flickers fast every frame -> latency, not bandwidth: each new
64-byte line was still a full HyperRAM round trip on the critical path while VIDC's FIFO only
holds 8 words (~1.3 us of pixels in the desktop mode). Fix: 8-line cache, next-line prefetch on
every read, writes invalidate (single-write-port LUTRAM).
Third test (video frames analysed): noise is made of desktop colours and changes per frame ->
VIDC FIFO underruns. Real cause: MEMC never interrupts a CPU access for DMA, and CPU cache
misses to HyperRAM take >1 us, longer than the 8-word VIDC FIFO lasts. Fix: video DMA FIFO
raised to 64 words (`vidc.v`, mega65 branch of the core).
Fourth test: RISC OS 3 splash box drawn cleanly, desktop turns to noise -> total bandwidth
(screen DMA + CPU + M2M scaler all on HyperRAM). Fix: first 512 KB of Archimedes RAM (the only
area VIDC DMA can address) moved into FPGA block RAM (128 x RAMB36). Also fixed a bridge bug:
IDLE must ignore STB while an ack is still showing (as sdram.v's `~wb_ack` does).
