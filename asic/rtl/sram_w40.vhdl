library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- DEPTH x 40 memory: bits 31..0 in 2048x32 macros, bits 39..32 in 4096x8
-- macros. Cheaper than wasting 24 bits of a 64-bit-wide macro.
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
end rtl;
