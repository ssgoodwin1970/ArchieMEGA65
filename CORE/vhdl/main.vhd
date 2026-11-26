----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- Wrapper for the MiSTer core that runs exclusively in the core's clock domanin
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_modes_pkg.all;

entity main is
   generic (
      G_VDNUM                 : natural                     -- amount of virtual drives
   );
   port (
      clk_main_i              : in  std_logic;              -- 42 MHz Archimedes system clock
      reset_soft_i            : in  std_logic;
      reset_hard_i            : in  std_logic;
      pause_i                 : in  std_logic;

      -- MiSTer core main clock speed:
      -- Make sure you pass very exact numbers here, because they are used for avoiding clock drift at derived clocks
      clk_main_speed_i        : in  natural;

      -- Video clock (96 MHz): all video_* outputs are in this clock domain
      clk_video_i             : in  std_logic;

      -- Video output
      video_ce_o              : out std_logic;
      video_ce_ovl_o          : out std_logic;
      video_red_o             : out std_logic_vector(7 downto 0);
      video_green_o           : out std_logic_vector(7 downto 0);
      video_blue_o            : out std_logic_vector(7 downto 0);
      video_vs_o              : out std_logic;
      video_hs_o              : out std_logic;
      video_hblank_o          : out std_logic;
      video_vblank_o          : out std_logic;

      -- Audio output (Signed PCM)
      audio_left_o            : out signed(15 downto 0);
      audio_right_o           : out signed(15 downto 0);

      -- M2M Keyboard interface
      kb_key_num_i            : in  integer range 0 to 79;    -- cycles through all MEGA65 keys
      kb_key_pressed_n_i      : in  std_logic;                -- low active: debounced feedback: is kb_key_num_i pressed right now?

      -- MEGA65 joysticks and paddles/mouse/potentiometers
      joy_1_up_n_i            : in  std_logic;
      joy_1_down_n_i          : in  std_logic;
      joy_1_left_n_i          : in  std_logic;
      joy_1_right_n_i         : in  std_logic;
      joy_1_fire_n_i          : in  std_logic;

      joy_2_up_n_i            : in  std_logic;
      joy_2_down_n_i          : in  std_logic;
      joy_2_left_n_i          : in  std_logic;
      joy_2_right_n_i         : in  std_logic;
      joy_2_fire_n_i          : in  std_logic;

      pot1_x_i                : in  std_logic_vector(7 downto 0);
      pot1_y_i                : in  std_logic_vector(7 downto 0);
      pot2_x_i                : in  std_logic_vector(7 downto 0);
      pot2_y_i                : in  std_logic_vector(7 downto 0);

      -- RISC OS ROM loader byte stream (main clock domain)
      rom_wr_i                : in  std_logic;
      rom_addr_i              : in  std_logic_vector(20 downto 0);
      rom_data_i              : in  std_logic_vector(7 downto 0);
      rom_busy_o              : out std_logic;

      -- Memory: 32-bit Avalon master (main clock domain), 1M words = 4 MB
      avm_write_o             : out std_logic;
      avm_read_o              : out std_logic;
      avm_address_o           : out std_logic_vector(19 downto 0);
      avm_writedata_o         : out std_logic_vector(31 downto 0);
      avm_byteenable_o        : out std_logic_vector(3 downto 0);
      avm_burstcount_o        : out std_logic_vector(7 downto 0);
      avm_readdata_i          : in  std_logic_vector(31 downto 0);
      avm_readdatavalid_i     : in  std_logic;
      avm_waitrequest_i       : in  std_logic;

      drive_led_o             : out std_logic;
      drive_led_col_o         : out std_logic_vector(23 downto 0)
   );
end entity main;

architecture synthesis of main is

component archie_main is
   port (
      clk_sys              : in  std_logic;
      clk_vid              : in  std_logic;
      reset_i              : in  std_logic;
      rom_loading_i        : in  std_logic;
      rom_wr_i             : in  std_logic;
      rom_addr_i           : in  std_logic_vector(20 downto 0);
      rom_data_i           : in  std_logic_vector(7 downto 0);
      rom_busy_o           : out std_logic;
      avm_write_o          : out std_logic;
      avm_read_o           : out std_logic;
      avm_address_o        : out std_logic_vector(19 downto 0);
      avm_writedata_o      : out std_logic_vector(31 downto 0);
      avm_byteenable_o     : out std_logic_vector(3 downto 0);
      avm_burstcount_o     : out std_logic_vector(7 downto 0);
      avm_readdata_i       : in  std_logic_vector(31 downto 0);
      avm_readdatavalid_i  : in  std_logic;
      avm_waitrequest_i    : in  std_logic;
      video_ce_o           : out std_logic;
      video_r_o            : out std_logic_vector(7 downto 0);
      video_g_o            : out std_logic_vector(7 downto 0);
      video_b_o            : out std_logic_vector(7 downto 0);
      video_hs_o           : out std_logic;
      video_vs_o           : out std_logic;
      video_hblank_o       : out std_logic;
      video_vblank_o       : out std_logic;
      audio_l_o            : out std_logic_vector(15 downto 0);
      audio_r_o            : out std_logic_vector(15 downto 0);
      joy0_n_i             : in  std_logic_vector(4 downto 0);
      joy1_n_i             : in  std_logic_vector(4 downto 0);
      fdd_led_o            : out std_logic;
      hdd_led_o            : out std_logic;
      dbg_rom_loaded_o     : out std_logic;
      dbg_running_o        : out std_logic;
      dbg_active_o         : out std_logic
   );
end component archie_main;

signal audio_l    : std_logic_vector(15 downto 0);
signal audio_r    : std_logic_vector(15 downto 0);
signal video_ce   : std_logic;
signal fdd_led    : std_logic;
signal hdd_led    : std_logic;
signal dbg_rom    : std_logic;
signal dbg_run    : std_logic;
signal dbg_act    : std_logic;

begin

   i_archie : archie_main
      port map (
         clk_sys              => clk_main_i,
         clk_vid              => clk_video_i,
         reset_i              => reset_soft_i or reset_hard_i,
         rom_loading_i        => '0',
         rom_wr_i             => rom_wr_i,
         rom_addr_i           => rom_addr_i,
         rom_data_i           => rom_data_i,
         rom_busy_o           => rom_busy_o,
         avm_write_o          => avm_write_o,
         avm_read_o           => avm_read_o,
         avm_address_o        => avm_address_o,
         avm_writedata_o      => avm_writedata_o,
         avm_byteenable_o     => avm_byteenable_o,
         avm_burstcount_o     => avm_burstcount_o,
         avm_readdata_i       => avm_readdata_i,
         avm_readdatavalid_i  => avm_readdatavalid_i,
         avm_waitrequest_i    => avm_waitrequest_i,
         video_ce_o           => video_ce,
         video_r_o            => video_red_o,
         video_g_o            => video_green_o,
         video_b_o            => video_blue_o,
         video_hs_o           => video_hs_o,
         video_vs_o           => video_vs_o,
         video_hblank_o       => video_hblank_o,
         video_vblank_o       => video_vblank_o,
         audio_l_o            => audio_l,
         audio_r_o            => audio_r,
         -- Archimedes joystick bits: {fire, right, left, down, up}, low active
         joy0_n_i             => joy_1_fire_n_i & joy_1_right_n_i & joy_1_left_n_i & joy_1_down_n_i & joy_1_up_n_i,
         joy1_n_i             => joy_2_fire_n_i & joy_2_right_n_i & joy_2_left_n_i & joy_2_down_n_i & joy_2_up_n_i,
         fdd_led_o            => fdd_led,
         hdd_led_o            => hdd_led,
         dbg_rom_loaded_o     => dbg_rom,
         dbg_running_o        => dbg_run,
         dbg_active_o         => dbg_act
      ); -- i_archie

   audio_left_o   <= signed(audio_l);
   audio_right_o  <= signed(audio_r);

   video_ce_o     <= video_ce;
   video_ce_ovl_o <= video_ce;

   -- Bring-up debug on the drive LED (temporary):
   --    off    = no ROM byte has arrived from the SD card
   --    red    = ROM arrived, Archimedes still held in reset
   --    yellow = out of reset, but no memory activity (CPU stopped)
   --    green  = running (memory bus busy)
   --    blue   = floppy / hard disk activity
   drive_led_o     <= dbg_rom or fdd_led or hdd_led;
   drive_led_col_o <= x"0000FF" when (fdd_led or hdd_led) = '1' else
                      x"FF0000" when dbg_run = '0' else
                      x"FFFF00" when dbg_act = '0' else
                      x"00FF00";

   -- Keyboard: the Archimedes keyboard controller comes in phase 3

end architecture synthesis;
