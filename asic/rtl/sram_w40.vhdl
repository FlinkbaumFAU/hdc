library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- DEPTH x 40 memory, macros chosen by depth:
--   DEPTH <= 256:  one 256x48 macro (8 bits unused)
--   DEPTH <= 1024: bits 31..0 in 1024x32, bits 39..32 in 1024x8
--   otherwise:     bits 31..0 in 2048x32 macros, bits 39..32 in 4096x8 macros
-- Splitting 32 + 8 is cheaper than wasting 24 bits of a 64-bit-wide macro.
entity sram_w40 is
    generic (
        DEPTH : integer
    );
    port (
        clk      : in  std_logic;
        we       : in  std_logic;
        addr     : in  std_logic_vector(15 downto 0);
        data_in  : in  std_logic_vector(39 downto 0);
        data_out : out std_logic_vector(39 downto 0)
    );
end sram_w40;

architecture rtl of sram_w40 is
begin
    g_256: if DEPTH <= 256 generate
        u_mem: entity work.sram_array
            generic map (DEPTH => DEPTH, WIDTH => 40, MACRO => "256x48", M_ABITS => 8, M_DBITS => 48)
            port map (
                clk      => clk,
                we       => we,
                addr     => addr,
                data_in  => data_in,
                data_out => data_out
            );
    end generate;

    g_1024: if DEPTH > 256 and DEPTH <= 1024 generate
        u_lo: entity work.sram_array
            generic map (DEPTH => DEPTH, WIDTH => 32, MACRO => "1024x32", M_ABITS => 10, M_DBITS => 32)
            port map (
                clk      => clk,
                we       => we,
                addr     => addr,
                data_in  => data_in(31 downto 0),
                data_out => data_out(31 downto 0)
            );

        u_hi: entity work.sram_array
            generic map (DEPTH => DEPTH, WIDTH => 8, MACRO => "1024x8", M_ABITS => 10, M_DBITS => 8)
            port map (
                clk      => clk,
                we       => we,
                addr     => addr,
                data_in  => data_in(39 downto 32),
                data_out => data_out(39 downto 32)
            );
    end generate;

    g_large: if DEPTH > 1024 generate
        u_lo: entity work.sram_array
            generic map (DEPTH => DEPTH, WIDTH => 32, MACRO => "2048x32", M_ABITS => 11, M_DBITS => 32)
            port map (
                clk      => clk,
                we       => we,
                addr     => addr,
                data_in  => data_in(31 downto 0),
                data_out => data_out(31 downto 0)
            );

        u_hi: entity work.sram_array
            generic map (DEPTH => DEPTH, WIDTH => 8, MACRO => "4096x8", M_ABITS => 12, M_DBITS => 8)
            port map (
                clk      => clk,
                we       => we,
                addr     => addr,
                data_in  => data_in(39 downto 32),
                data_out => data_out(39 downto 32)
            );
    end generate;
end rtl;
