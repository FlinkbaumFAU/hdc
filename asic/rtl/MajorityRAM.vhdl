library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ASIC (IHP SG13) implementation of MajorityRAM: same interface as
-- ../../MajorityRAM.vhdl, mapped to one 256x48 single-port macro.
-- The write address wins on write cycles; the accelerator never needs a
-- read in the same cycle as a write.
entity MajorityRAM is
    generic (
        DEPTH : integer := 250;
        WIDTH : integer := 40
    );
    Port (
        clk   : in  STD_LOGIC;
        we    : in  STD_LOGIC;
        waddr : in  integer range 0 to DEPTH-1;
        raddr : in  integer range 0 to DEPTH-1;
        din   : in  STD_LOGIC_VECTOR(WIDTH-1 downto 0);
        dout  : out STD_LOGIC_VECTOR(WIDTH-1 downto 0)
    );
end MajorityRAM;

architecture sg13 of MajorityRAM is
    signal addr : std_logic_vector(15 downto 0);
begin
    assert DEPTH <= 256 and WIDTH <= 48
        report "MajorityRAM: exceeds one 256x48 macro" severity failure;

    addr <= std_logic_vector(to_unsigned(waddr, 16)) when we = '1'
            else std_logic_vector(to_unsigned(raddr, 16));

    u_mem: entity work.sram_array
        generic map (DEPTH => DEPTH, WIDTH => WIDTH, MACRO => "256x48", M_ABITS => 8, M_DBITS => 48)
        port map (
            clk      => clk,
            we       => we,
            addr     => addr,
            data_in  => din,
            data_out => dout
        );
end sg13;
