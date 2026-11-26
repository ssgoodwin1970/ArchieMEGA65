// Archie_MiSTer core wrapper for the MEGA65 (MiSTer2MEGA65).
//
// Replaces Archie.sv from Archie_MiSTer: everything the MiSTer HPS (ARM/Linux)
// did is either done here in the FPGA or by the M2M framework.
//
// Clocks:
//   clk_sys : 42 MHz  (CPU, MEMC, IOC, audio, memory bus)
//   clk_vid : 96 MHz  (VIDC pixel output; pixel rates made with fractional clock enables)
//
// Memory:
//   The core's Wishbone bus is turned into a 32-bit Avalon master. Word address
//   space is 1M x 32 bit (4 MB): 0..2 MB = Archimedes RAM, 2..4 MB = RISC OS ROM.
//   The SDRAM controller of the MiSTer version returned 4 words for every read
//   (wrap-around burst inside an aligned 16 byte block) and kept acking while the
//   master held STB. This bridge does exactly the same, so MEMC/Amber/DMA behave
//   as on the MiSTer.
//
// ROM loading:
//   rom_wr_i delivers the ROM file byte by byte (byte address rom_addr_i). Bytes are
//   packed little-endian into 32-bit words and written to the ROM area. The core is
//   held in reset while rom_loading_i is high.

`timescale 1 ps / 1 ps

module archie_main
#(
   parameter ROM_QUIET_BITS = 20          // core stays in reset 2^N clk_sys cycles after the last ROM byte
)
(
   input             clk_sys,
   input             clk_vid,
   input             reset_i,            // clk_sys domain, active high
   input             rom_loading_i,      // clk_sys domain: ROM download in progress

   // ROM loader byte stream (clk_sys)
   input             rom_wr_i,
   input      [20:0] rom_addr_i,
   input       [7:0] rom_data_i,
   output            rom_busy_o,

   // Avalon memory master (clk_sys), 32-bit words
   output reg        avm_write_o,
   output reg        avm_read_o,
   output reg [19:0] avm_address_o,
   output reg [31:0] avm_writedata_o,
   output reg  [3:0] avm_byteenable_o,
   output reg  [7:0] avm_burstcount_o,
   input      [31:0] avm_readdata_i,
   input             avm_readdatavalid_i,
   input             avm_waitrequest_i,

   // Video (clk_vid)
   output            video_ce_o,
   output      [7:0] video_r_o,
   output      [7:0] video_g_o,
   output      [7:0] video_b_o,
   output            video_hs_o,
   output            video_vs_o,
   output reg        video_hblank_o,
   output reg        video_vblank_o,

   // Audio (clk_sys), signed PCM
   output     [15:0] audio_l_o,
   output     [15:0] audio_r_o,

   // Joysticks, low active: {fire, right, left, down, up}
   input       [4:0] joy0_n_i,
   input       [4:0] joy1_n_i,

   // MEGA65 keyboard (M2M scanner) and 1351 mouse in port 1
   input       [6:0] key_num_i,
   input             key_pressed_n_i,
   input       [7:0] mouse_x_i,
   input       [7:0] mouse_y_i,

   output            fdd_led_o,
   output            hdd_led_o,

   // Debug status (clk_sys): shown on the MEGA65 drive LED
   output            dbg_rom_loaded_o,   // at least one ROM byte arrived
   output            dbg_running_o,      // core is out of reset
   output reg        dbg_active_o        // CPU/DMA used the memory bus in the last ~0.2 s
);

///////////////////////////////////////////////////////////////////////////////
// Resets
///////////////////////////////////////////////////////////////////////////////

// The M2M firmware holds the core in reset while it loads the ROM. As an extra
// safety net the core also stays in reset until a ROM has arrived and for ~25 ms
// after the last ROM byte.
reg        rom_loaded = 0;
reg [ROM_QUIET_BITS-1:0] rom_quiet = 0;
always @(posedge clk_sys) begin
   if (rom_wr_i) begin
      rom_loaded <= 1'b1;
      rom_quiet  <= 0;
   end else if (~&rom_quiet)
      rom_quiet  <= rom_quiet + 1'd1;
end

wire core_reset = reset_i | rom_loading_i | ~rom_loaded | ~&rom_quiet;

assign dbg_rom_loaded_o = rom_loaded;
assign dbg_running_o    = ~core_reset;
reg [22:0] dbg_cnt = 0;
always @(posedge clk_sys) begin
   if (core_stb_out & core_cyc_out & ~core_reset) begin
      dbg_cnt      <= 0;
      dbg_active_o <= 1'b1;
   end else if (~&dbg_cnt)
      dbg_cnt      <= dbg_cnt + 1'd1;
   else
      dbg_active_o <= 1'b0;
end

reg [1:0] video_reset_sync         = 2'b11;
reg [1:0] video_command_reset_sync = 2'b11;
wire video_reset         = video_reset_sync[1];
wire video_command_reset = video_command_reset_sync[1];
always @(posedge clk_vid) begin
   video_reset_sync         <= {video_reset_sync[0], core_reset};
   video_command_reset_sync <= {video_command_reset_sync[0], core_reset};
end

///////////////////////////////////////////////////////////////////////////////
// Archimedes
///////////////////////////////////////////////////////////////////////////////

wire        core_ack_in;
wire        core_stb_out;
wire        core_cyc_out;
wire        core_we_o;
wire  [3:0] core_sel_o;
wire  [2:0] core_cti_o;
wire [31:0] core_data_out;
reg  [31:0] core_data_in;
wire [23:2] core_address_out;

wire  [1:0] selpix;
wire        hires_mono;
wire  [1:0] pixbaseclk_select;

wire        core_hs, core_vs, core_de;
wire  [3:0] core_r, core_g, core_b;

wire        i2c_din, i2c_dout, i2c_clock;

reg         ce_pix;
wire  [7:0] kbd_out_data, kbd_in_data;
wire        kbd_out_strobe, kbd_in_strobe;
reg         ce_vid;
reg         ce_aud;

archimedes_top #(42000000) ARCHIMEDES
(
   .CLKCPU_I          ( clk_sys             ),
   .CLKPIX_I          ( clk_vid             ),
   .CEPIX_I           ( ce_pix              ),
   .CEVID_I           ( ce_vid              ),
   .SELPIX_O          ( selpix              ),
   .HIRES_MONO_O      ( hires_mono          ),

   .CLKAUD_I          ( clk_sys             ),
   .CEAUD_I           ( ce_aud              ),

   .RESET_I           ( core_reset          ),
   .RESET_VIDEO_I     ( video_reset         ),
   .RESET_VIDEO_CPU_I ( core_reset          ),
   .RESET_COMMAND_I   ( video_command_reset ),

   .MEM_ACK_I         ( core_ack_in         ),
   .MEM_ERR_I         ( 1'b0                ),
   .MEM_RTY_I         ( 1'b0                ),
   .MEM_DAT_I         ( core_data_in        ),
   .MEM_DAT_O         ( core_data_out       ),
   .MEM_ADDR_O        ( core_address_out    ),
   .MEM_STB_O         ( core_stb_out        ),
   .MEM_CYC_O         ( core_cyc_out        ),
   .MEM_SEL_O         ( core_sel_o          ),
   .MEM_WE_O          ( core_we_o           ),
   .MEM_CTI_O         ( core_cti_o          ),

   .HSYNC             ( core_hs             ),
   .VSYNC             ( core_vs             ),

   .VIDEO_R           ( core_r              ),
   .VIDEO_G           ( core_g              ),
   .VIDEO_B           ( core_b              ),
   .VIDEO_EN          ( core_de             ),

   .AUDIO_L           ( audio_l_o           ),
   .AUDIO_R           ( audio_r_o           ),

   .I2C_DOUT          ( i2c_din             ),
   .I2C_DIN           ( i2c_dout            ),
   .I2C_CLOCK         ( i2c_clock           ),

   .fdd_led           ( fdd_led_o           ),
   .hdd_led           ( hdd_led_o           ),

   // Floppy: not connected yet (phase 4)
   .img_mounted       ( 2'b00               ),
   .img_size          ( 32'd0               ),
   .img_wp            ( 1'b1                ),
   .sd_lba            (                     ),
   .sd_rd             (                     ),
   .sd_wr             (                     ),
   .sd_ack            ( 1'b0                ),
   .sd_buff_addr      ( 8'd0                ),
   .sd_buff_dout      ( 16'd0               ),
   .sd_buff_din       (                     ),
   .sd_buff_wr        ( 1'b0                ),

   // IDE: not connected yet (phase 6)
   .ide_req           (                     ),
   .ide_address       ( 5'd0                ),
   .ide_write         ( 1'b0                ),
   .ide_writedata     ( 16'd0               ),
   .ide_read          ( 1'b0                ),
   .ide_readdata      (                     ),

   // Keyboard controller (archie_kbd.v): reset handshake now, keys in phase 3
   .KBD_OUT_DATA      ( kbd_out_data        ),
   .KBD_OUT_STROBE    ( kbd_out_strobe      ),
   .KBD_IN_DATA       ( kbd_in_data         ),
   .KBD_IN_STROBE     ( kbd_in_strobe       ),

   .JOYSTICK0         ( joy0_n_i            ),
   .JOYSTICK1         ( joy1_n_i            ),
   .VIDBASECLK_O      ( pixbaseclk_select   ),
   .VIDSYNCPOL_O      (                     )
);

archie_kbd #(.CLK_HZ(42000000)) KEYBOARD
(
   .clk         ( clk_sys        ),
   .reset       ( core_reset     ),
   .host_data   ( kbd_out_data   ),
   .host_strobe ( kbd_out_strobe ),
   .kbd_data    ( kbd_in_data    ),
   .kbd_strobe  ( kbd_in_strobe  ),
   .key_num_i       ( key_num_i       ),
   .key_pressed_n_i ( key_pressed_n_i ),
   .mouse_x_i       ( mouse_x_i       ),
   .mouse_y_i       ( mouse_y_i       ),
   .mouse_left_n_i  ( joy0_n_i[4]     ),   // port 1 fire  = left button
   .mouse_right_n_i ( joy0_n_i[0]     )    // port 1 up    = right button
);

///////////////////////////////////////////////////////////////////////////////
// Pixel clock enables (clk_vid = 96 MHz)
//
// The MiSTer version retunes a PLL per VIDC clock family. Here the pixel rate is
// made with a fractional accumulator on a fixed 96 MHz clock (the same method
// Archie.sv uses for its 60 Hz mode). Mode 23 (hi-res mono) runs natively at
// 96 MHz: a pixel every clock, a VIDC tick every 4th clock.
///////////////////////////////////////////////////////////////////////////////

localparam VIDCLK = 96000000;

reg [1:0] pixbaseclk_sync1 = 0, pixbaseclk_sync2 = 0;
always @(posedge clk_vid) begin
   pixbaseclk_sync1 <= pixbaseclk_select;
   pixbaseclk_sync2 <= pixbaseclk_sync1;
end

wire [31:0] vratio[16];
assign vratio[ 0] =  8000000; assign vratio[ 1] = 12000000; assign vratio[ 2] = 16000000; assign vratio[ 3] = 24000000;
assign vratio[ 4] =  8391666; assign vratio[ 5] = 12587500; assign vratio[ 6] = 16783333; assign vratio[ 7] = 25175000;
assign vratio[ 8] = 12000000; assign vratio[ 9] = 18000000; assign vratio[10] = 24000000; assign vratio[11] = 36000000;
assign vratio[12] =  8000000; assign vratio[13] = 12000000; assign vratio[14] = 16000000; assign vratio[15] = 24000000;

wire [3:0]  vmode = {pixbaseclk_sync2, selpix};
reg  [31:0] vclk  = 8000000;
reg  [31:0] vsum  = 0;
wire [31:0] vsum_next = vsum + vclk;
reg  [1:0]  mono_cnt = 0;

always @(posedge clk_vid) begin
   vclk   <= vratio[vmode];
   ce_pix <= 1'b0;
   ce_vid <= 1'b0;
   if (video_reset) begin
      vsum     <= 0;
      mono_cnt <= 0;
   end else if (hires_mono) begin
      ce_pix   <= 1'b1;
      mono_cnt <= mono_cnt + 1'd1;
      ce_vid   <= (mono_cnt == 2'd3);
   end else begin
      vsum <= vsum_next;
      if (vsum_next >= VIDCLK) begin
         vsum   <= vsum_next - VIDCLK;
         ce_pix <= 1'b1;
         ce_vid <= 1'b1;
      end
   end
end

///////////////////////////////////////////////////////////////////////////////
// Video output for M2M: active high syncs, 8-bit colour, h/v blank from DE
///////////////////////////////////////////////////////////////////////////////

assign video_ce_o = ce_pix;
assign video_r_o  = {core_r, core_r};
assign video_g_o  = {core_g, core_g};
assign video_b_o  = {core_b, core_b};
assign video_hs_o = ~core_hs;
assign video_vs_o = ~core_vs;

reg old_hs    = 0;
reg line_de   = 0;
always @(posedge clk_vid) begin
   if (ce_pix) begin
      video_hblank_o <= ~core_de;
      old_hs         <= video_hs_o;
      if (core_de) begin
         line_de        <= 1'b1;
         video_vblank_o <= 1'b0;
      end
      // at the start of each hsync: a line without any visible pixel means vertical blank
      if (~old_hs & video_hs_o) begin
         if (~line_de) video_vblank_o <= 1'b1;
         line_de <= 1'b0;
      end
   end
end

///////////////////////////////////////////////////////////////////////////////
// Audio clock enable (from Archie.sv)
///////////////////////////////////////////////////////////////////////////////

localparam CLKSYS = 42000000;

wire [31:0] aratio[4];
assign aratio[0] = 1000000; assign aratio[1] = 1048958; assign aratio[2] = 1500000; assign aratio[3] = 1000000;

reg  [31:0] asum = 0, aclk = 1000000, aclk1 = 1000000;
wire [31:0] asum_next = asum + aclk;
always @(posedge clk_sys) begin
   aclk1  <= aratio[pixbaseclk_select];
   aclk   <= aclk1;
   ce_aud <= 1'b0;
   asum   <= asum_next;
   if (asum_next >= CLKSYS) begin
      asum   <= asum_next - CLKSYS;
      ce_aud <= 1'b1;
   end
end

///////////////////////////////////////////////////////////////////////////////
// CMOS RAM (I2C EEPROM model, defaults from Archie_MiSTer cmos.mif)
///////////////////////////////////////////////////////////////////////////////

wire [7:0] eep_din, eep_addr;
reg  [7:0] eep_dout;
wire       eep_read, eep_write;

reg eep_ce;
reg [1:0] eep_cnt = 0;
always @(posedge clk_sys) begin
   eep_cnt <= eep_cnt + 1'd1;
   eep_ce  <= (eep_cnt == 2'd0);
end

EEPROM_24C0x eeprom
(
   .clk           ( clk_sys    ),
   .ce            ( eep_ce     ),
   .reset         ( core_reset ),
   .SCL           ( i2c_clock  ),
   .SDA_in        ( i2c_din    ),
   .SDA_out       ( i2c_dout   ),
   .type_24C01    ( 1'b0       ),
   .E_id          ( 3'd0       ),
   .WC_n          ( 1'b0       ),
   .data_from_ram ( eep_dout   ),
   .data_to_ram   ( eep_din    ),
   .ram_addr      ( eep_addr   ),
   .ram_read      ( eep_read   ),
   .ram_write     ( eep_write  ),
   .ram_done      ( 1'b1       )
);

reg [7:0] cmos_mem [0:255];
initial $readmemh("archie_cmos.mem", cmos_mem);
always @(posedge clk_sys) begin
   if (eep_write) cmos_mem[eep_addr] <= eep_din;
   eep_dout <= cmos_mem[eep_addr];
end

///////////////////////////////////////////////////////////////////////////////
// ROM loader: pack bytes into 32-bit words
///////////////////////////////////////////////////////////////////////////////

reg [31:0] rom_word;
reg [18:0] rom_waddr;
reg        rom_pending = 0;
reg        rom_done;

assign rom_busy_o = rom_pending;

always @(posedge clk_sys) begin
   if (rom_done) rom_pending <= 1'b0;
   if (rom_wr_i) begin
      rom_word[rom_addr_i[1:0]*8 +: 8] <= rom_data_i;
      if (rom_addr_i[1:0] == 2'd3) begin
         rom_waddr   <= rom_addr_i[20:2];
         rom_pending <= 1'b1;
      end
   end
end

///////////////////////////////////////////////////////////////////////////////
// Wishbone -> Avalon bridge with read cache and next-line prefetch
//
// Behaves towards the core like Archie_MiSTer sdram.v: every read returns up to
// 4 words (wrap-around inside the aligned 16 byte block) on consecutive clocks
// while the master holds STB.
//
// HyperRAM (shared with the M2M scaler) answers far slower than the MiSTer SDRAM.
// Video DMA streams the screen in 16 byte requests and VIDC's FIFO only holds
// 8 words, so a full HyperRAM round trip on the critical path makes the FIFO run
// dry (flickering noise on screen). Therefore:
//   - reads are served from an 8-line cache of 64 byte lines (one 16-word burst each)
//   - every read of line L queues a background prefetch of line L+1, done while
//     the bus is idle, so sequential streams (video, sound, code) hit the cache
//   - writes go straight through to HyperRAM and drop a cached copy of the line
//     (this bridge is the only writer, so the cache stays coherent)
///////////////////////////////////////////////////////////////////////////////

// 2 MB RAM (addresses above alias) and 2 MB ROM (core address bit 22)
wire [19:0] core_waddr = {core_address_out[22], core_address_out[20:2]};
wire [15:0] core_line  = core_waddr[19:4];

// The first 512 KB of Archimedes RAM live in FPGA block RAM. VIDC's video,
// cursor and sound DMA can only address this area (MEMC's DMA pointers are 19
// bits), so the screen never waits for HyperRAM. 128K x 32 bit = 128 RAMB36.
localparam PREFETCH_EN = 0;                           // next-line prefetch (only needed when the screen was in HyperRAM)
localparam LOWRAM_EN   = 1;                           // 0 = all RAM in HyperRAM (A/B test switch)
localparam LOWRAM_BITS = 17;                          // 2^17 words = 512 KB
wire        core_low = LOWRAM_EN && (core_waddr[19:LOWRAM_BITS] == 0);

(* ram_style = "block" *)
reg [31:0] lowram [0:(1<<LOWRAM_BITS)-1];
reg [LOWRAM_BITS-1:0] low_addr;
reg [31:0] low_wdata;
reg  [3:0] low_we = 4'b0000;
reg [31:0] low_q;

integer lb;
always @(posedge clk_sys) begin
   for (lb = 0; lb < 4; lb = lb + 1)
      if (low_we[lb]) lowram[low_addr][lb*8 +: 8] <= low_wdata[lb*8 +: 8];
   low_q <= lowram[low_addr];
end

localparam ST_IDLE  = 3'd0;
localparam ST_WRITE = 3'd1;
localparam ST_FILL  = 3'd2;
localparam ST_ACK   = 3'd3;
localparam ST_ROM   = 3'd4;
localparam ST_HIT   = 3'd5;
localparam ST_LOW   = 3'd6;          // block RAM read: words arrive one clock after their address
localparam ST_LOWW  = 3'd7;          // block RAM write: ack one clock later

localparam WAYS = 8;

reg  [2:0] state = ST_IDLE;

(* ram_style = "distributed" *)
reg [31:0] cdata [0:WAYS*16-1];    // {way[2:0], word[3:0]}
reg [15:0] ctag  [0:WAYS-1];
reg [WAYS-1:0] cvalid = {WAYS{1'b0}};
reg  [2:0] victim = 3'd0;

reg  [2:0] cway;                   // way being read / filled
reg  [3:0] cword;                  // next word to hand to the core
reg  [3:0] fcnt;                   // words received during a fill
reg        fill_pf;                // current fill is a prefetch (no core waiting)
reg  [1:0] acks;                   // acks given in this cycle (wraps after 4)
reg        wb_ack = 0;

reg        pf_req = 1'b0;          // a prefetch is queued
reg [15:0] pf_line;                // line to prefetch

assign core_ack_in = wb_ack;

// hit detection for the core request and for the queued prefetch
wire [WAYS-1:0] hit_vec, pf_vec;
genvar gw;
generate for (gw = 0; gw < WAYS; gw = gw + 1) begin : g_hit
   assign hit_vec[gw] = cvalid[gw] && (ctag[gw] == core_line);
   assign pf_vec[gw]  = cvalid[gw] && (ctag[gw] == pf_line);
end endgenerate
wire       hit    = |hit_vec;
wire       pf_hit = |pf_vec || (state == ST_FILL && ctag[cway] == pf_line);
reg  [2:0] hit_way;
integer h;
always @* begin
   hit_way = 3'd0;
   for (h = 0; h < WAYS; h = h + 1) if (hit_vec[h]) hit_way = h[2:0];
end

// cache data RAM: single write port (line fills), asynchronous read
always @(posedge clk_sys)
   if (state == ST_FILL && avm_readdatavalid_i)
      cdata[{cway, fcnt}] <= avm_readdata_i;
wire [31:0] cache_q = cdata[{cway, cword}];

reg [1:0] low_word;                // word index inside the 16 byte block (wraps)
reg       low_first;

always @(posedge clk_sys) begin
   wb_ack   <= 1'b0;
   rom_done <= 1'b0;
   low_we   <= 4'b0000;

   if (state == ST_FILL && avm_readdatavalid_i) fcnt <= fcnt + 1'd1;

   case (state)
      ST_IDLE: begin
         if (rom_pending & ~rom_done) begin
            cvalid           <= {WAYS{1'b0}};      // ROM download: drop the cache
            pf_req           <= 1'b0;
            avm_write_o      <= 1'b1;
            avm_read_o       <= 1'b0;
            avm_address_o    <= {1'b1, rom_waddr};
            avm_writedata_o  <= rom_word;
            avm_byteenable_o <= 4'b1111;
            avm_burstcount_o <= 8'd1;
            state            <= ST_ROM;
         end else if (core_stb_out & core_cyc_out & ~wb_ack & ~core_reset & core_low) begin
            // first 512 KB: block RAM, never HyperRAM
            low_addr <= core_waddr[LOWRAM_BITS-1:0];
            if (core_we_o) begin
               low_wdata <= core_data_out;
               low_we    <= core_sel_o;
               state     <= ST_LOWW;
            end else begin
               low_word  <= core_waddr[1:0];
               low_first <= 1'b1;
               state     <= ST_LOW;
            end
         end else if (core_stb_out & core_cyc_out & ~wb_ack & ~core_reset) begin
            if (core_we_o) begin
               if (hit) cvalid[hit_way] <= 1'b0;   // write through, drop the cached copy
               if (pf_req && pf_line == core_line) pf_req <= 1'b0;
               avm_write_o      <= 1'b1;
               avm_address_o    <= core_waddr;
               avm_writedata_o  <= core_data_out;
               avm_byteenable_o <= core_sel_o;
               avm_burstcount_o <= 8'd1;
               state            <= ST_WRITE;
            end else begin
               // queue the next line for prefetching
               pf_line <= core_line + 1'd1;
               pf_req  <= PREFETCH_EN;
               cword   <= core_waddr[3:0];
               if (hit) begin
                  cway  <= hit_way;
                  state <= ST_HIT;
               end else begin
                  cway             <= victim;
                  fcnt             <= 4'd0;
                  fill_pf          <= 1'b0;
                  cvalid[victim]   <= 1'b0;
                  ctag[victim]     <= core_line;
                  victim           <= victim + 1'd1;
                  avm_read_o       <= 1'b1;
                  avm_address_o    <= {core_line, 4'b0000};
                  avm_byteenable_o <= 4'b1111;
                  avm_burstcount_o <= 8'd16;
                  state            <= ST_FILL;
               end
            end
         end else if (pf_req & ~core_reset) begin
            pf_req <= 1'b0;
            if (~pf_hit && (!LOWRAM_EN || pf_line[15:LOWRAM_BITS-4] != 0)) begin
               cway             <= victim;
               fcnt             <= 4'd0;
               fill_pf          <= 1'b1;
               cvalid[victim]   <= 1'b0;
               ctag[victim]     <= pf_line;
               victim           <= victim + 1'd1;
               avm_read_o       <= 1'b1;
               avm_address_o    <= {pf_line, 4'b0000};
               avm_byteenable_o <= 4'b1111;
               avm_burstcount_o <= 8'd16;
               state            <= ST_FILL;
            end
         end
      end

      ST_ROM: if (~avm_waitrequest_i) begin
         avm_write_o <= 1'b0;
         rom_done    <= 1'b1;
         state       <= ST_IDLE;
      end

      ST_WRITE: if (~avm_waitrequest_i) begin
         avm_write_o <= 1'b0;
         wb_ack      <= 1'b1;
         acks        <= 2'd1;
         state       <= ST_ACK;
      end

      ST_FILL: begin
         if (~avm_waitrequest_i) avm_read_o <= 1'b0;
         if (avm_readdatavalid_i && fcnt == 4'd15) begin
            cvalid[cway] <= 1'b1;
            state        <= fill_pf ? ST_IDLE : ST_HIT;
         end
      end

      // first word of a read (cache hit or line just filled)
      ST_HIT: begin
         core_data_in <= cache_q;
         cword        <= {cword[3:2], cword[1:0] + 2'd1};
         wb_ack       <= 1'b1;
         acks         <= 2'd1;
         state        <= ST_ACK;
      end

      // keep acking (up to 4 in total) while the master holds STB, as sdram.v does
      ST_ACK: begin
         if (core_stb_out & core_cyc_out & acks != 2'd0) begin
            core_data_in <= cache_q;
            cword        <= {cword[3:2], cword[1:0] + 2'd1};
            wb_ack       <= 1'b1;
            acks         <= acks + 1'd1;
         end else
            state        <= ST_IDLE;
      end

      ST_LOWW: begin
         wb_ack <= 1'b1;
         acks   <= 2'd1;
         state  <= ST_ACK;
      end

      // block RAM reads: hand out up to 4 words (wrapping inside the 16 byte
      // block) on consecutive clocks while the master holds STB, like sdram.v
      ST_LOW: begin
         if (low_first) begin
            // address of word 0 was presented in IDLE; present word 1 now
            low_first <= 1'b0;
            low_addr  <= {low_addr[LOWRAM_BITS-1:2], low_word + 2'd1};
            low_word  <= low_word + 2'd1;
            acks      <= 2'd0;
         end else if (acks == 2'd0 || (core_stb_out & core_cyc_out)) begin
            core_data_in <= low_q;
            wb_ack       <= 1'b1;
            low_addr     <= {low_addr[LOWRAM_BITS-1:2], low_word + 2'd1};
            low_word     <= low_word + 2'd1;
            acks         <= acks + 1'd1;
            if (acks == 2'd3) state <= ST_IDLE;
         end else
            state <= ST_IDLE;
      end

      default: state <= ST_IDLE;
   endcase
end

endmodule
