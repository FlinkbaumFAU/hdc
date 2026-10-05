library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Encoded hypervector of the current sample (one WIDTH-bit word per chunk).
-- Simple dual-port: synchronous write, 1-cycle registered read.
-- The accelerator never reads and writes in the same cycle, so the ASIC
-- version (asic/rtl/MajorityRAM.vhdl) can map this to a single-port macro.
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

architecture Behavioral of MajorityRAM is
    type ram_t is array (0 to DEPTH-1) of std_logic_vector(WIDTH-1 downto 0);
    signal ram : ram_t := (others => (others => '0'));

    attribute ram_style : string;
    attribute ram_style of ram : signal is "block";
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                ram(waddr) <= din;
            end if;

            dout <= ram(raddr);
        end if;
    end process;
end Behavioral;
