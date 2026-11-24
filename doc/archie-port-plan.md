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
