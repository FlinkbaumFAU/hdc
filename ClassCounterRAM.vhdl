library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

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

architecture Behavioral of ClassCounterRAM is

    subtype word_t is std_logic_vector(WIDTH-1 downto 0);
    type ram_t is array (0 to DEPTH-1) of word_t;

    signal ram : ram_t := (others => (others => '0'));

    attribute ram_style : string;
    attribute ram_style of ram : signal is "block";

begin

    process(clk)
        variable a : integer range 0 to DEPTH-1;
    begin
        if rising_edge(clk) then
            -- Wichtig:
            -- Für RAM-Inference keine Schutzlogik mit if addr < DEPTH.
            -- Der Accelerator muss gültige Adressen liefern.
            -- In der 1-class-counter-Variante ist DEPTH = CHUNKS_PER_VEC * WORD_WIDTH.
            a := to_integer(unsigned(addr));

            if we = '1' then
                ram(a) <= data_in;
            end if;

            -- synchroner 1-Takt-Read
            data_out <= ram(a);
        end if;
    end process;

end Behavioral;