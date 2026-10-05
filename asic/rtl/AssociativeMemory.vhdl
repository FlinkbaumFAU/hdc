library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- ASIC (IHP SG13) implementation of AssociativeMemory: same interface as ../../AssociativeMemory.vhdl,
-- storage mapped to SRAM macros via sram_w40.
entity AssociativeMemory is
    generic (
        D : integer := 10016;
        K : integer := 5;
        WORD_WIDTH : integer := 40
    );
    Port (
        clk      : in  STD_LOGIC;
        we       : in  STD_LOGIC;
        addr     : in  STD_LOGIC_VECTOR(15 downto 0);
        data_in  : in  STD_LOGIC_VECTOR(WORD_WIDTH-1 downto 0);
        data_out : out STD_LOGIC_VECTOR(WORD_WIDTH-1 downto 0)
    );
end AssociativeMemory;

architecture sg13 of AssociativeMemory is
    constant CHUNKS_PER_VEC : integer := (D + WORD_WIDTH - 1) / WORD_WIDTH;
begin
    assert WORD_WIDTH = 40 report "AssociativeMemory: SRAM mapping assumes WORD_WIDTH = 40" severity failure;

    u_mem: entity work.sram_w40
        generic map (DEPTH => CHUNKS_PER_VEC * K)
        port map (
            clk      => clk,
            we       => we,
            addr     => addr,
            data_in  => data_in,
            data_out => data_out
        );
end sg13;
