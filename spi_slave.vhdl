library ieee;
use ieee.std_logic_1164.all;

entity spi_slave is
    port(
        sclk_i : in  std_logic;
        mosi_i : in  std_logic;
        miso_o : out std_logic;
        cs_n_i : in  std_logic;

        tx_byte0_i : in  std_logic_vector(7 downto 0);
        tx_byte1_i : in  std_logic_vector(7 downto 0);

        rx_byte0_o : out std_logic_vector(7 downto 0);
        rx_byte1_o : out std_logic_vector(7 downto 0);

        pair_done_o     : out std_logic;
        preload_point_o : out std_logic;
        first_pair_o    : out std_logic
    );
end entity;

architecture rtl of spi_slave is
    signal in_shift    : std_logic_vector(7 downto 0) := (others => '0');
    signal byte0_latch : std_logic_vector(7 downto 0) := (others => '0');
    signal byte1_latch : std_logic_vector(7 downto 0) := (others => '0');
    signal bit_cnt     : integer range 0 to 7 := 0;
    signal on_byte1    : std_logic := '0';

    signal preload_initial_byte0 : std_logic_vector(7 downto 0) := (others => '0');
    signal preload_initial_byte1 : std_logic_vector(7 downto 0) := (others => '0');
    signal preload_cont_byte0    : std_logic_vector(7 downto 0) := (others => '0');
    signal preload_cont_byte1    : std_logic_vector(7 downto 0) := (others => '0');

    signal out_bit_cnt   : integer range 0 to 7 := 0;
    signal out_on_byte1  : std_logic := '0';
    signal out_first_pair: std_logic := '1';
begin
    rx_byte0_o <= byte0_latch;
    rx_byte1_o <= byte1_latch;
    first_pair_o <= out_first_pair;

    -- Combinational, not registered, so hdc_spi_loader sees the edge in
    -- the same cycle it happens rather than one cycle late.
    pair_done_o     <= '1' when (bit_cnt = 7 and on_byte1 = '1') else '0';
    preload_point_o <= '1' when (out_bit_cnt = 7 and out_on_byte1 = '1') else '0';

    miso_o <= preload_initial_byte0(7 - out_bit_cnt) when (out_first_pair = '1' and out_on_byte1 = '0') else
              preload_initial_byte1(7 - out_bit_cnt) when (out_first_pair = '1' and out_on_byte1 = '1') else
              preload_cont_byte0(7 - out_bit_cnt)    when out_on_byte1 = '0'
         else preload_cont_byte1(7 - out_bit_cnt);

    -- First-pair preload, once per session.
    process(cs_n_i)
    begin
        if falling_edge(cs_n_i) then
            preload_initial_byte0 <= tx_byte0_i;
            preload_initial_byte1 <= tx_byte1_i;
        end if;
    end process;

    process(sclk_i, cs_n_i)
    begin
        if cs_n_i = '1' then
            bit_cnt   <= 0;
            on_byte1  <= '0';
        elsif rising_edge(sclk_i) then
            in_shift  <= in_shift(6 downto 0) & mosi_i;

            if bit_cnt = 7 then
                bit_cnt <= 0;
                if on_byte1 = '0' then
                    byte0_latch <= in_shift(6 downto 0) & mosi_i;
                    on_byte1    <= '1';
                else
                    byte1_latch <= in_shift(6 downto 0) & mosi_i;
                    on_byte1    <= '0';
                end if;
            else
                bit_cnt <= bit_cnt + 1;
            end if;
        end if;
    end process;

    process(sclk_i, cs_n_i)
    begin
        if cs_n_i = '1' then
            out_bit_cnt    <= 0;
            out_on_byte1   <= '0';
            out_first_pair <= '1';
        elsif falling_edge(sclk_i) then
            if out_bit_cnt = 7 then
                out_bit_cnt <= 0;
                if out_on_byte1 = '1' then
                    preload_cont_byte0 <= tx_byte0_i;
                    preload_cont_byte1 <= tx_byte1_i;
                    out_first_pair     <= '0';
                end if;
                out_on_byte1 <= not out_on_byte1;
            else
                out_bit_cnt <= out_bit_cnt + 1;
            end if;
        end if;
    end process;

end architecture;
