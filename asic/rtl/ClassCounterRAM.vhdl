library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- ASIC (IHP SG13) implementation of ClassCounterRAM: same interface as
-- ../../ClassCounterRAM.vhdl, storage mapped to 1024x16 (DEPTH <= 1024) or
-- 4096x16 SRAM macros.
entity ClassCounterRAM is
    generic (
        DEPTH : integer := 10040;
        WIDTH : integer := 11
    );
    Port (
        clk      : in  STD_LOGIC;
        we       : in  STD_LOGIC;
        addr     : in  STD_LOGIC_VECTOR(15 downto 0);
        data_in  : in  STD_LOGIC_VECTOR(WIDTH-1 downto 0);
        data_out : out STD_LOGIC_VECTOR(WIDTH-1 downto 0)
    );
end ClassCounterRAM;

architecture sg13 of ClassCounterRAM is
begin
    g_1024: if DEPTH <= 1024 generate
        u_mem: entity work.sram_array
            generic map (DEPTH => DEPTH, WIDTH => WIDTH, MACRO => "1024x16", M_ABITS => 10, M_DBITS => 16)
            port map (
                clk      => clk,
                we       => we,
                addr     => addr,
                data_in  => data_in,
                data_out => data_out
            );
    end generate;

    g_large: if DEPTH > 1024 generate
        u_mem: entity work.sram_array
            generic map (DEPTH => DEPTH, WIDTH => WIDTH, MACRO => "4096x16", M_ABITS => 12, M_DBITS => 16)
            port map (
                clk      => clk,
                we       => we,
                addr     => addr,
                data_in  => data_in,
                data_out => data_out
            );
    end generate;
end sg13;
