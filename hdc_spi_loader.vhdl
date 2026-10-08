library ieee;
use ieee.std_logic_1164.all;

entity hdc_spi_loader is
    port(
        clk   : in  std_logic;
        reset : in  std_logic;

        rx_byte_o  : out std_logic_vector(7 downto 0);
        rx_valid_o : out std_logic;

        tx_start_i : in  std_logic;
        tx_data_i  : in  std_logic_vector(7 downto 0);
        tx_busy_o  : out std_logic;

        sclk_i : in  std_logic;
        mosi_i : in  std_logic;
        miso_o : out std_logic;
        cs_n_i : in  std_logic
    );
end entity;

architecture rtl of hdc_spi_loader is
    constant OPCODE_SEND   : std_logic_vector(7 downto 0) := x"A5";
    constant STATUS_VALID  : std_logic_vector(7 downto 0) := x"01";
    constant STATUS_NONE    : std_logic_vector(7 downto 0) := x"00";

    signal rx_byte0, rx_byte1 : std_logic_vector(7 downto 0);
    signal spi_tx_byte0, spi_tx_byte1 : std_logic_vector(7 downto 0);

    signal pair_done, preload_point, first_pair : std_logic;

    -- SPI (sclk/cs) domain
    signal tx_req_spi_sync   : std_logic_vector(1 downto 0) := (others => '0');
    signal tx_req_seen_spi   : std_logic := '0';
    signal tx_shadow_byte    : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_ack_toggle_spi : std_logic := '0';
    signal tx_pending_valid  : std_logic;

    signal tx_in_flight_valid_initial : std_logic := '0';
    signal tx_in_flight_valid_cont    : std_logic := '0';
    signal tx_in_flight_valid         : std_logic;

    signal rx_toggle_spi : std_logic := '0';
    signal rx_byte_spi   : std_logic_vector(7 downto 0) := (others => '0');

    -- clk (system) domain
    signal tx_req_toggle_sys   : std_logic := '0';
    signal tx_pending_byte     : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_ack_sys_sync     : std_logic_vector(1 downto 0) := (others => '0');
    signal tx_req_latched      : std_logic := '0';
    signal tx_req_data_latched : std_logic_vector(7 downto 0) := (others => '0');
    signal transport_busy      : std_logic;

    signal rx_toggle_sys_sync : std_logic_vector(1 downto 0) := (others => '0');
    signal rx_toggle_seen_sys : std_logic := '0';
begin

    tx_pending_valid <= '1' when tx_req_seen_spi /= tx_ack_toggle_spi else '0';
    spi_tx_byte0 <= STATUS_VALID when tx_pending_valid = '1' else STATUS_NONE;
    spi_tx_byte1 <= tx_shadow_byte;

    tx_in_flight_valid <= tx_in_flight_valid_initial when first_pair = '1' else tx_in_flight_valid_cont;

    u_spi: entity work.spi_slave
        port map (
            sclk_i          => sclk_i,
            mosi_i          => mosi_i,
            miso_o          => miso_o,
            cs_n_i          => cs_n_i,
            tx_byte0_i      => spi_tx_byte0,
            tx_byte1_i      => spi_tx_byte1,
            rx_byte0_o      => rx_byte0,
            rx_byte1_o      => rx_byte1,
            pair_done_o     => pair_done,
            preload_point_o => preload_point,
            first_pair_o    => first_pair
        );

   process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                tx_req_toggle_sys   <= '0';
                tx_pending_byte     <= (others => '0');
                tx_ack_sys_sync     <= (others => '0');
                tx_req_latched      <= '0';
                tx_req_data_latched <= (others => '0');
            else
                tx_ack_sys_sync <= tx_ack_sys_sync(0) & tx_ack_toggle_spi;

                if tx_req_latched = '1' and transport_busy = '0' then
                    tx_pending_byte   <= tx_req_data_latched;
                    tx_req_toggle_sys <= not tx_req_toggle_sys;
                    tx_req_latched    <= '0';
                end if;

                if tx_start_i = '1' then
                    tx_req_latched      <= '1';
                    tx_req_data_latched <= tx_data_i;
                end if;
            end if;
        end if;
    end process;

    transport_busy <= '1' when tx_req_toggle_sys /= tx_ack_sys_sync(1) else '0';
    tx_busy_o      <= '1' when (transport_busy = '1') or (tx_req_latched = '1') else '0';

   process(sclk_i, reset)
    begin
        if reset = '1' then
            tx_req_spi_sync <= (others => '0');
            tx_req_seen_spi <= '0';
            tx_shadow_byte  <= (others => '0');
        elsif rising_edge(sclk_i) then
            tx_req_spi_sync <= tx_req_spi_sync(0) & tx_req_toggle_sys;

            if tx_req_spi_sync(1) /= tx_req_seen_spi then
                tx_req_seen_spi <= tx_req_spi_sync(1);
                tx_shadow_byte  <= tx_pending_byte;
            end if;
        end if;
    end process;

    process(cs_n_i, reset)
    begin
        if reset = '1' then
            tx_in_flight_valid_initial <= '0';
        elsif falling_edge(cs_n_i) then
            tx_in_flight_valid_initial <= tx_pending_valid;
        end if;
    end process;

   process(sclk_i, reset)
    begin
        if reset = '1' then
            tx_in_flight_valid_cont <= '0';
            rx_toggle_spi           <= '0';
            rx_byte_spi             <= (others => '0');
        elsif falling_edge(sclk_i) then
            if preload_point = '1' then
                tx_in_flight_valid_cont <= tx_pending_valid;

                if rx_byte0 = OPCODE_SEND then
                    rx_byte_spi   <= rx_byte1;
                    rx_toggle_spi <= not rx_toggle_spi;
                end if;
            end if;
        end if;
    end process;

    process(sclk_i, reset)
    begin
        if reset = '1' then
            tx_ack_toggle_spi <= '0';
        elsif rising_edge(sclk_i) then
            if pair_done = '1' then
                if tx_in_flight_valid = '1' then
                    tx_ack_toggle_spi <= tx_req_seen_spi;
                end if;
            end if;
        end if;
    end process;

   process(clk)
    begin
        if rising_edge(clk) then
            rx_valid_o <= '0';

            if reset = '1' then
                rx_toggle_sys_sync <= (others => '0');
                rx_toggle_seen_sys <= '0';
                rx_byte_o          <= (others => '0');
            else
                rx_toggle_sys_sync <= rx_toggle_sys_sync(0) & rx_toggle_spi;

                if rx_toggle_sys_sync(1) /= rx_toggle_seen_sys then
                    rx_toggle_seen_sys <= rx_toggle_sys_sync(1);
                    rx_byte_o          <= rx_byte_spi;
                    rx_valid_o         <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture;
