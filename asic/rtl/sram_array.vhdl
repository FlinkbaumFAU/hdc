library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- DEPTH x WIDTH single-port memory built from a grid of identical
-- SG13 SRAM macros: BANKS (depth) x COLS (width).
-- Same timing as the inferred FPGA memories: synchronous write, 1-cycle
-- registered read. Unlike them, the output keeps the last read value
-- during write cycles; the accelerator never relies on read-during-write.
entity sram_array is
    generic (
        DEPTH   : integer;
        WIDTH   : integer;
        MACRO   : string;   -- see sg13_sram_macro
        M_ABITS : integer;  -- macro address bits
        M_DBITS : integer   -- macro data bits
    );
    port (
        clk      : in  std_logic;
        we       : in  std_logic;
        addr     : in  std_logic_vector(15 downto 0);
        data_in  : in  std_logic_vector(WIDTH-1 downto 0);
        data_out : out std_logic_vector(WIDTH-1 downto 0)
    );
end sram_array;

architecture rtl of sram_array is
    constant M_DEPTH : integer := 2**M_ABITS;
    constant BANKS   : integer := (DEPTH + M_DEPTH - 1) / M_DEPTH;
    constant COLS    : integer := (WIDTH + M_DBITS - 1) / M_DBITS;
    constant PWIDTH  : integer := COLS * M_DBITS;

    type bank_data_t is array (0 to BANKS-1) of std_logic_vector(PWIDTH-1 downto 0);

    signal din_pad  : std_logic_vector(PWIDTH-1 downto 0);
    signal bank_out : bank_data_t;
    signal bank     : integer range 0 to BANKS-1;
    signal bank_q   : integer range 0 to BANKS-1 := 0;
begin
    assert DEPTH <= 2**16 severity failure;

    din_pad <= std_logic_vector(resize(unsigned(data_in), PWIDTH));

    g_one_bank: if BANKS = 1 generate
        bank <= 0;
    end generate;

    g_multi_bank: if BANKS > 1 generate
        bank <= to_integer(unsigned(addr(15 downto M_ABITS)));
    end generate;

    g_banks: for b in 0 to BANKS-1 generate
        signal sel : std_logic;
    begin
        sel <= '1' when bank = b else '0';

        g_cols: for c in 0 to COLS-1 generate
            u_macro: entity work.sg13_sram_macro
                generic map (MACRO => MACRO, ABITS => M_ABITS, DBITS => M_DBITS)
                port map (
                    clk  => clk,
                    men  => sel,
                    wen  => we,
                    ren  => not we,
                    addr => addr(M_ABITS-1 downto 0),
                    din  => din_pad((c+1)*M_DBITS-1 downto c*M_DBITS),
                    dout => bank_out(b)((c+1)*M_DBITS-1 downto c*M_DBITS)
                );
        end generate;
    end generate;

    -- Remember which bank the pending read came from.
    process(clk)
    begin
        if rising_edge(clk) then
            if we = '0' then
                bank_q <= bank;
            end if;
        end if;
    end process;

    data_out <= bank_out(bank_q)(WIDTH-1 downto 0);
end rtl;
