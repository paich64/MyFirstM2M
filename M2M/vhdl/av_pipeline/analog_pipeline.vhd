----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- Complete pipeline processing of analog audio and video output (VGA and 3.5 mm)
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_modes_pkg.all;
use work.qnice_tools.all;

entity analog_pipeline is
   generic (
      G_VGA_DX               : natural;              -- Actual format of video from Core (in pixels).
      G_VGA_DY               : natural;
      G_FONT_FILE            : string;
      G_FONT_DX              : natural;
      G_FONT_DY              : natural
   );
   port (
      -- Input from Core (video and audio)
      video_clk_i            : in  std_logic;
      video_rst_i            : in  std_logic;
      video_ce_i             : in  std_logic;
      video_red_i            : in  std_logic_vector(7 downto 0);
      video_green_i          : in  std_logic_vector(7 downto 0);
      video_blue_i           : in  std_logic_vector(7 downto 0);
      video_hs_i             : in  std_logic;
      video_vs_i             : in  std_logic;
      video_hblank_i         : in  std_logic;
      video_vblank_i         : in  std_logic;
      audio_clk_i            : in  std_logic;
      audio_rst_i            : in  std_logic;
      audio_left_i           : in  signed(15 downto 0); -- Signed PCM format
      audio_right_i          : in  signed(15 downto 0); -- Signed PCM format

      -- Video output (VGA)
      vga_clk_i              : in  std_logic;
      vga_rst_i              : in  std_logic;
      vga_red_o              : out std_logic_vector(7 downto 0);
      vga_green_o            : out std_logic_vector(7 downto 0);
      vga_blue_o             : out std_logic_vector(7 downto 0);
      vga_hs_o               : out std_logic;
      vga_vs_o               : out std_logic;
      vdac_clk_o             : out std_logic;
      vdac_syncn_o           : out std_logic;
      vdac_blankn_o          : out std_logic;

      -- Audio output (3.5 mm jack)
      pwm_l_o                : out std_logic;
      pwm_r_o                : out std_logic;

      -- Connect to QNICE and Video RAM
      video_osm_cfg_enable_i : in  std_logic;
      video_osm_cfg_xy_i     : in  std_logic_vector(15 downto 0);
      video_osm_cfg_dxdy_i   : in  std_logic_vector(15 downto 0);
      video_osm_vram_addr_o  : out std_logic_vector(15 downto 0);
      video_osm_vram_data_i  : in  std_logic_vector(15 downto 0);

      -- QNICE connection to ascal's mode register
      qnice_ascal_mode_i     : in unsigned(4 downto 0);

      -- QNICE device for interacting with the Polyphase filter coefficients
      qnice_poly_clk_i       : in std_logic;
      qnice_poly_dw_i        : in unsigned(9 downto 0);
      qnice_poly_a_i         : in unsigned(6+3 downto 0);    -- FRAC+3 downto 0, if we change FRAC below, we need to change quite some code, also in the M2M Firmware
      qnice_poly_wr_i        : in std_logic;

      -- Connect to HyperRAM controller
      hr_clk_i               : in  std_logic;
      hr_rst_i               : in  std_logic;
      hr_write_o             : out std_logic;
      hr_read_o              : out std_logic;
      hr_address_o           : out std_logic_vector(31 downto 0);
      hr_writedata_o         : out std_logic_vector(15 downto 0);
      hr_byteenable_o        : out std_logic_vector(1 downto 0);
      hr_burstcount_o        : out std_logic_vector(7 downto 0);
      hr_readdata_i          : in  std_logic_vector(15 downto 0);
      hr_readdatavalid_i     : in  std_logic;
      hr_waitrequest_i       : in  std_logic
   );
end entity analog_pipeline;

architecture synthesis of analog_pipeline is

   signal reset_na               : std_logic;            -- Asynchronous reset, active low

   -- MiSTer video pipeline signals
   signal vga_red                : unsigned(7 downto 0);
   signal vga_green              : unsigned(7 downto 0);
   signal vga_blue               : unsigned(7 downto 0);
   signal vga_hs                 : std_logic;
   signal vga_vs                 : std_logic;
   signal vga_de                 : std_logic;

   constant C_AVM_ADDRESS_SIZE   : integer := 19;
   constant C_AVM_DATA_SIZE      : integer := 128;
   signal vga_video_mode         : video_modes_t;
   signal vga_htotal             : integer;
   signal vga_hsstart            : integer;
   signal vga_hsend              : integer;
   signal vga_hdisp              : integer;
   signal vga_vtotal             : integer;
   signal vga_vsstart            : integer;
   signal vga_vsend              : integer;
   signal vga_vdisp              : integer;

   -- Auto-calculate display dimensions based on an 4:3 aspect ratio
   signal vga_hmin               : integer;
   signal vga_hmax               : integer;
   signal vga_vmin               : integer;
   signal vga_vmax               : integer;

   signal hr_wide_write          : std_logic;
   signal hr_wide_read           : std_logic;
   signal hr_wide_address        : std_logic_vector(C_AVM_ADDRESS_SIZE-1 downto 0);
   signal hr_wide_writedata      : std_logic_vector(C_AVM_DATA_SIZE-1 downto 0);
   signal hr_wide_byteenable     : std_logic_vector(C_AVM_DATA_SIZE/8-1 downto 0);
   signal hr_wide_burstcount     : std_logic_vector(7 downto 0);
   signal hr_wide_readdata       : std_logic_vector(C_AVM_DATA_SIZE-1 downto 0);
   signal hr_wide_readdatavalid  : std_logic;
   signal hr_wide_waitrequest    : std_logic;

begin

   ---------------------------------------------------------------------------------------------
   -- Analog output - Audio part (3.5 mm jack)
   ---------------------------------------------------------------------------------------------

   -- Convert the C64's PCM output to pulse density modulation
   i_pcm2pdm : entity work.pcm_to_pdm
      port map
      (
         cpuclock         => audio_clk_i,
         pcm_left         => audio_left_i,
         pcm_right        => audio_right_i,
         -- Pulse Density Modulation (PDM is supposed to sound better than PWM on MEGA65)
         pdm_left         => pwm_l_o,
         pdm_right        => pwm_r_o,
         audio_mode       => '0'         -- 0=PDM, 1=PWM
      ); -- i_pcm2pdm


   ---------------------------------------------------------------------------------------------
   -- Analog output - Video part (VGA)
   ---------------------------------------------------------------------------------------------

   vga_video_mode <= C_PAL_720_576_50;
   vga_htotal     <= vga_video_mode.H_PIXELS + vga_video_mode.H_FP + vga_video_mode.H_PULSE + vga_video_mode.H_BP;
   vga_hsstart    <= vga_video_mode.H_PIXELS + vga_video_mode.H_FP;
   vga_hsend      <= vga_video_mode.H_PIXELS + vga_video_mode.H_FP + vga_video_mode.H_PULSE;
   vga_hdisp      <= vga_video_mode.H_PIXELS;
   vga_vtotal     <= vga_video_mode.V_PIXELS + vga_video_mode.V_FP + vga_video_mode.V_PULSE + vga_video_mode.V_BP;
   vga_vsstart    <= vga_video_mode.V_PIXELS + vga_video_mode.V_FP;
   vga_vsend      <= vga_video_mode.V_PIXELS + vga_video_mode.V_FP + vga_video_mode.V_PULSE;
   vga_vdisp      <= vga_video_mode.V_PIXELS;
   vga_hmin       <= 0;
   vga_hmax       <= vga_video_mode.H_PIXELS-1;
   vga_vmin       <= 0;
   vga_vmax       <= vga_video_mode.V_PIXELS-1;

   reset_na <= not (video_rst_i or vga_rst_i or hr_rst_i);

   i_ascal : entity work.ascal
      generic map (
         MASK      => x"ff",
         RAMBASE   => x"0000_0000",

         -- ascal needs an input buffer according to this formula: dx * dy * 3 bytes (RGB) per pixel and then rounded up
         -- to the next power of two
         RAMSIZE   => to_unsigned(2**f_log2(G_VGA_DX * G_VGA_DY * 3), 32),

         INTER     => false,        -- Not needed: Progressive input only
         HEADER    => false,        -- Not needed: Used on MiSTer to read the sampled image back from the ARM side to do screenshots. The header provides informations such as image size.
         DOWNSCALE => false,        -- Not needed: We use ascal only to upscale
         DOWNSCALE_NN => true,      -- Not needed: true = remove logic
         BYTESWAP  => true,
         ADAPTIVE  => true,         -- Needed for advanced scanlines emulation in polyphase mode
         PALETTE   => false,        -- Not needed: Only useful for the framebuffer mode, where the scaler is used to upscale a framebuffer in RAM, without using the scaler input.
         PALETTE2  => false,        -- Not needed: Same, for framebuffer 256 colours mode.
         FRAC      => 6,            -- 2^value subpixels; MiSTer starts to settle on FRAC => 8, but this older version of ascal does not seem to support 8 (at C64 still at 6)
         OHRES     => 2048,         -- Maximum horizontal output resolution. (There is no parameter for vertical resolution.)
         IHRES     => 1024,         -- Maximum horizontal input resolution. (Also here no parameter for vertical.)
         N_DW      => C_AVM_DATA_SIZE,
         N_AW      => C_AVM_ADDRESS_SIZE,
         N_BURST   => 256           -- 256 bytes per burst
      )
      port map (
         -- Input video
         i_r               => unsigned(video_red_i),        -- input
         i_g               => unsigned(video_green_i),      -- input
         i_b               => unsigned(video_blue_i),       -- input
         i_hs              => video_hs_i,                   -- input
         i_vs              => video_vs_i,                   -- input
         i_fl              => '0',                          -- input
         i_de              => not (video_hblank_i or video_vblank_i), -- input
         i_ce              => video_ce_i,                   -- input
         i_clk             => video_clk_i,                  -- input

         -- Output video
         o_r               => vga_red,                      -- output
         o_g               => vga_green,                    -- output
         o_b               => vga_blue,                     -- output
         o_hs              => vga_hs,                       -- output
         o_vs              => vga_vs,                       -- output
         o_de              => vga_de,                       -- output
         o_vbl             => open,                         -- output
         o_ce              => '1',                          -- input
         o_clk             => vga_clk_i,                    -- input

         -- Border colour R G B
         o_border          => X"000000",                    -- input

         -- Framebuffer mode
         o_fb_ena          => '0',                          -- input: do not use framebuffer mode
         o_fb_hsize        => 0,                            -- input
         o_fb_vsize        => 0,                            -- input
         o_fb_format       => "000101",                     -- input: 101=24bpp: 8-bit for R, G and B
         o_fb_base         => x"0000_0000",                 -- input
         o_fb_stride       => (others => '0'),              -- input

         -- Framebuffer palette in 8bpp mode
         pal1_clk          => '0',                          -- input
         pal1_dw           => x"000000000000",              -- input
         pal1_dr           => open,                         -- output
         pal1_a            => "0000000",                    -- input
         pal1_wr           => '0',                          -- input
         pal_n             => '0',                          -- input

         pal2_clk          => '0',                          -- input
         pal2_dw           => x"000000",                    -- input
         pal2_dr           => open,                         -- output
         pal2_a            => "00000000",                   -- input
         pal2_wr           => '0',                          -- input

         -- Low lag PLL tuning
         o_lltune          => open,                         -- output

         -- Input video parameters
         iauto             => '1',                          -- input
         himin             => 0,                            -- input
         himax             => 0,                            -- input
         vimin             => 0,                            -- input
         vimax             => 0,                            -- input

         -- Detected input image size
         i_hdmax           => open,                         -- output
         i_vdmax           => open,                         -- output

         -- Output video parameters
         run               => '1',                          -- input
         freeze            => '0',                          -- input
         mode              => qnice_ascal_mode_i,           -- input

         -- SYNC  |_________________________/"""""""""\_______|
         -- DE    |""""""""""""""""""\________________________|
         -- RGB   |    <#IMAGE#>      ^HDISP                  |
         --            ^HMIN   ^HMAX        ^HSSTART  ^HSEND  ^HTOTAL
         htotal            => vga_htotal,                   -- input
         hsstart           => vga_hsstart,                  -- input
         hsend             => vga_hsend,                    -- input
         hdisp             => vga_hdisp,                    -- input
         vtotal            => vga_vtotal,                   -- input
         vsstart           => vga_vsstart,                  -- input
         vsend             => vga_vsend,                    -- input
         vdisp             => vga_vdisp,                    -- input
         hmin              => vga_hmin,                     -- input
         hmax              => vga_hmax,                     -- input
         vmin              => vga_vmin,                     -- input
         vmax              => vga_vmax,                     -- input

         -- Scaler format. 00=16bpp 565, 01=24bpp 10=32bpp
         format            => "00",                         -- input: 16bpp

         -- Polyphase filter coefficients (not used by us)
         poly_clk          => qnice_poly_clk_i,             -- input
         poly_dw           => qnice_poly_dw_i,              -- input
         poly_a            => qnice_poly_a_i,               -- input
         poly_wr           => qnice_poly_wr_i,              -- input

         -- Avalon Memory interface
         avl_clk           => hr_clk_i,                     -- input
         avl_waitrequest   => hr_wide_waitrequest and not hr_wide_write,  -- input
         avl_readdata      => hr_wide_readdata,             -- input
         avl_readdatavalid => hr_wide_readdatavalid,        -- input
         avl_burstcount    => hr_wide_burstcount,           -- output
         avl_writedata     => hr_wide_writedata,            -- output
         avl_address       => hr_wide_address,              -- output
         avl_write         => hr_wide_write,                -- output
         avl_read          => hr_wide_read,                 -- output
         avl_byteenable    => hr_wide_byteenable,           -- output

         -- Asynchronous reset, active low
         reset_na          => reset_na                      -- input
      ); -- i_ascal

   i_avm_decrease : entity work.avm_decrease
      generic map (
         G_SLAVE_ADDRESS_SIZE  => C_AVM_ADDRESS_SIZE,
         G_SLAVE_DATA_SIZE     => C_AVM_DATA_SIZE,
         G_MASTER_ADDRESS_SIZE => 22,  -- HyperRAM size is 4 MWords = 8 MBytes.
         G_MASTER_DATA_SIZE    => 16
      )
      port map (
         clk_i                 => hr_clk_i,
         rst_i                 => hr_rst_i,
         s_avm_write_i         => '0',
         s_avm_read_i          => hr_wide_read,
         s_avm_address_i       => hr_wide_address,
         s_avm_writedata_i     => hr_wide_writedata,
         s_avm_byteenable_i    => hr_wide_byteenable,
         s_avm_burstcount_i    => hr_wide_burstcount,
         s_avm_readdata_o      => hr_wide_readdata,
         s_avm_readdatavalid_o => hr_wide_readdatavalid,
         s_avm_waitrequest_o   => hr_wide_waitrequest,
         m_avm_write_o         => hr_write_o,
         m_avm_read_o          => hr_read_o,
         m_avm_address_o       => hr_address_o(21 downto 0), -- MSB defaults to zero
         m_avm_writedata_o     => hr_writedata_o,
         m_avm_byteenable_o    => hr_byteenable_o,
         m_avm_burstcount_o    => hr_burstcount_o,
         m_avm_readdata_i      => hr_readdata_i,
         m_avm_readdatavalid_i => hr_readdatavalid_i,
         m_avm_waitrequest_i   => hr_waitrequest_i
      ); -- i_avm_decrease


   i_video_overlay : entity work.video_overlay
      generic  map (
         G_VGA_DX         => G_VGA_DX,
         G_VGA_DY         => G_VGA_DY,
         G_FONT_FILE      => G_FONT_FILE,
         G_FONT_DX        => G_FONT_DX,
         G_FONT_DY        => G_FONT_DY
      )
      port map (
         vga_clk_i        => vga_clk_i,
         vga_ce_i         => '1',
         vga_red_i        => std_logic_vector(vga_red),
         vga_green_i      => std_logic_vector(vga_green),
         vga_blue_i       => std_logic_vector(vga_blue),
         vga_hs_i         => vga_hs,
         vga_vs_i         => vga_vs,
         vga_de_i         => vga_de,
         vga_cfg_enable_i => video_osm_cfg_enable_i,
         vga_cfg_xy_i     => video_osm_cfg_xy_i,
         vga_cfg_dxdy_i   => video_osm_cfg_dxdy_i,
         vga_vram_addr_o  => video_osm_vram_addr_o,
         vga_vram_data_i  => video_osm_vram_data_i,
         vga_ce_o         => open,
         vga_red_o        => vga_red_o,
         vga_green_o      => vga_green_o,
         vga_blue_o       => vga_blue_o,
         vga_hs_o         => vga_hs_o,
         vga_vs_o         => vga_vs_o,
         vga_de_o         => open
      ); -- i_video_overlay_video

   -- Make the MEGA65 VDAC (ADV7125BCPZ170) output the image:
   --
   -- Excerpts taken from the data sheet Rev D, page 8, table 6:
   --    "sync":  If sync information is not required on the green channel, the SYNC input should be tied to Logic 0.
   --    "blank": A Logic 0 on this control input drives the analog outputs [...] to the blanking level.
   -- So as we do not do any "sync on green", we set sync to 0 and since we do not want to use the VDAC to
   -- blank the screen (i.e. set the analog R, G and B to 0), we hard-wire blank to 1.
   --
   -- The fact that we phase-shift the VDAC's clock by 90 degrees is the outcome of experiements, i.e.
   -- empiric knowledge: We get a much sharper / crisper image. The true root cause is unknown, but it works reliably.
   vdac_syncn_o  <= '0';
   vdac_blankn_o <= '1';
   vdac_clk_o    <= not video_clk_i;

end architecture synthesis;

