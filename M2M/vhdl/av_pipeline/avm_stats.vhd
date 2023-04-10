library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.numeric_std_unsigned.all;

-- This collects statistics on an Avalon interface

entity avm_stats is
   generic (
      G_FREQ_HZ      : integer := 100_000_000;  -- 100 MHz
      G_ADDRESS_SIZE : integer;
      G_DATA_SIZE    : integer
   );
   port (
      clk_i               : in  std_logic;
      rst_i               : in  std_logic;
      avm_write_i         : in  std_logic;
      avm_read_i          : in  std_logic;
      avm_address_i       : in  std_logic_vector(G_ADDRESS_SIZE-1 downto 0);
      avm_writedata_i     : in  std_logic_vector(G_DATA_SIZE-1 downto 0);
      avm_byteenable_i    : in  std_logic_vector(G_DATA_SIZE/8-1 downto 0);
      avm_burstcount_i    : in  std_logic_vector(7 downto 0);
      avm_readdata_i      : in  std_logic_vector(G_DATA_SIZE-1 downto 0);
      avm_readdatavalid_i : in  std_logic;
      avm_waitrequest_i   : in  std_logic
   );
end entity avm_stats;

architecture synthesis of avm_stats is

   signal cnt             : natural range 0 to G_FREQ_HZ-1;
   signal cnt_write       : natural range 0 to G_FREQ_HZ-1;
   signal cnt_read        : natural range 0 to G_FREQ_HZ-1;
   signal cnt_wr_zero     : natural range 0 to G_FREQ_HZ-1;
   signal cnt_rd_zero     : natural range 0 to G_FREQ_HZ-1;
   signal cnt_idle        : natural range 0 to G_FREQ_HZ-1;
   signal cnt_busy        : natural range 0 to G_FREQ_HZ-1;
   signal cnt_wait_wr     : natural range 0 to G_FREQ_HZ-1;
   signal cnt_wait_rd     : natural range 0 to G_FREQ_HZ-1;
   signal cnt_wait_wr_max : natural range 0 to G_FREQ_HZ-1;
   signal cnt_wait_rd_max : natural range 0 to G_FREQ_HZ-1;
   signal cnt_wait_wr_tot : natural range 0 to G_FREQ_HZ-1;
   signal cnt_wait_rd_tot : natural range 0 to G_FREQ_HZ-1;
   signal adr_max_wr      : std_logic_vector(G_ADDRESS_SIZE-1 downto 0);
   signal adr_max_rd      : std_logic_vector(G_ADDRESS_SIZE-1 downto 0);

   attribute mark_debug                        : string;
   attribute mark_debug of cnt                 : signal is "true";
   attribute mark_debug of cnt_write           : signal is "true";
   attribute mark_debug of cnt_read            : signal is "true";
   attribute mark_debug of cnt_wr_zero         : signal is "true";
   attribute mark_debug of cnt_rd_zero         : signal is "true";
   attribute mark_debug of cnt_idle            : signal is "true";
   attribute mark_debug of cnt_busy            : signal is "true";
   attribute mark_debug of cnt_wait_wr         : signal is "true";
   attribute mark_debug of cnt_wait_rd         : signal is "true";
   attribute mark_debug of cnt_wait_wr_max     : signal is "true";
   attribute mark_debug of cnt_wait_rd_max     : signal is "true";
   attribute mark_debug of cnt_wait_wr_tot     : signal is "true";
   attribute mark_debug of cnt_wait_rd_tot     : signal is "true";
   attribute mark_debug of adr_max_wr          : signal is "true";
   attribute mark_debug of adr_max_rd          : signal is "true";
   attribute mark_debug of avm_write_i         : signal is "true";
   attribute mark_debug of avm_read_i          : signal is "true";
   attribute mark_debug of avm_address_i       : signal is "true";
   attribute mark_debug of avm_readdatavalid_i : signal is "true";
   attribute mark_debug of avm_waitrequest_i   : signal is "true";

begin

   p_cnt : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if cnt_wait_wr > cnt_wait_wr_max then
            cnt_wait_wr_max <= cnt_wait_wr;
         end if;
         if cnt_wait_rd > cnt_wait_rd_max then
            cnt_wait_rd_max <= cnt_wait_rd;
         end if;

         if avm_waitrequest_i = '0' then
            cnt_wait_wr <= 0;
            cnt_wait_rd <= 0;
            if avm_write_i = '1' then
               if avm_address_i > adr_max_wr then
                  adr_max_wr <= avm_address_i;
               end if;
               cnt_write <= cnt_write + 1;
               if avm_address_i = 0 then
                  cnt_wr_zero <= cnt_wr_zero + 1;
               end if;
            elsif avm_read_i = '1' then
               if avm_address_i > adr_max_rd then
                  adr_max_rd <= avm_address_i;
               end if;
               cnt_read <= cnt_read + to_integer(avm_burstcount_i);
               if avm_address_i = 0 then
                  cnt_rd_zero <= cnt_rd_zero + 1;
               end if;
            else
               cnt_idle <= cnt_idle + 1;
            end if;
         else
            cnt_busy <= cnt_busy + 1;

            if avm_write_i = '1' then
               cnt_wait_wr     <= cnt_wait_wr + 1;
               cnt_wait_wr_tot <= cnt_wait_wr_tot  + 1;
            elsif avm_read_i = '1' then
               cnt_wait_rd     <= cnt_wait_rd + 1;
               cnt_wait_rd_tot <= cnt_wait_rd_tot  + 1;
            end if;
         end if;

         if cnt = G_FREQ_HZ-1 then
            cnt             <= 0;
            cnt_write       <= 0;
            cnt_read        <= 0;
            cnt_wr_zero     <= 0;
            cnt_rd_zero     <= 0;
            cnt_idle        <= 0;
            cnt_busy        <= 0;
            cnt_wait_wr     <= 0;
            cnt_wait_rd     <= 0;
            cnt_wait_wr_max <= 0;
            cnt_wait_rd_max <= 0;
            cnt_wait_wr_tot <= 0;
            cnt_wait_rd_tot <= 0;
            adr_max_wr      <= (others => '0');
            adr_max_rd      <= (others => '0');
         else
            cnt <= cnt + 1;
         end if;

         if rst_i = '1' then
            cnt             <= 0;
            cnt_write       <= 0;
            cnt_read        <= 0;
            cnt_wr_zero     <= 0;
            cnt_rd_zero     <= 0;
            cnt_idle        <= 0;
            cnt_busy        <= 0;
            cnt_wait_wr     <= 0;
            cnt_wait_rd     <= 0;
            cnt_wait_wr_max <= 0;
            cnt_wait_rd_max <= 0;
            cnt_wait_wr_tot <= 0;
            cnt_wait_rd_tot <= 0;
            adr_max_wr      <= (others => '0');
            adr_max_rd      <= (others => '0');
         end if;
      end if;
   end process p_cnt;

end architecture synthesis;

