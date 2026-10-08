library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdc_cmd_loader is
    port(
        clk   : in  std_logic;
        reset : in  std_logic;

        rx_byte_i  : in  std_logic_vector(7 downto 0);
        rx_valid_i : in  std_logic;

        tx_start_o : out std_logic;
        tx_data_o  : out std_logic_vector(7 downto 0);
        tx_busy_i  : in  std_logic;

        load_mode_o   : out std_logic;
        mem_sel_o     : out std_logic_vector(1 downto 0);
        mem_we_o      : out std_logic;
        mem_addr_o    : out std_logic_vector(15 downto 0);
        mem_data_in_o : out std_logic_vector(39 downto 0);

        feature_value_o : out std_logic_vector(31 downto 0);
        feature_valid_o : out std_logic;
        start_o         : out std_logic;
        train_mode_o    : out std_logic;
        finalize_o      : out std_logic;
        label_o         : out std_logic_vector(2 downto 0);

        done_i             : in  std_logic;
        recognized_class_i : in  std_logic_vector(2 downto 0);
        mem_data_out_i     : in  std_logic_vector(39 downto 0)
    );
end entity;

architecture rtl of hdc_cmd_loader is
    constant ACK_BYTE           : std_logic_vector(7 downto 0) := x"4B";
    constant FINALIZE_DONE_BYTE : std_logic_vector(7 downto 0) := x"5A";

    type cmd_state_t is (
        WAIT_CMD,

        WRITE_ADDR0, WRITE_ADDR1,
        WRITE_D0, WRITE_D1, WRITE_D2, WRITE_D3, WRITE_D4,

        WBULK_SEL, WBULK_ADDR0, WBULK_ADDR1, WBULK_CNT0, WBULK_CNT1,
        WBULK_D0, WBULK_D1, WBULK_D2, WBULK_D3, WBULK_D4, WBULK_ACK,

        READ_SEL, READ_ADDR0, READ_ADDR1, READ_WAIT, READ_WAIT2,
        READ_TX0, READ_TX0_BUSY,
        READ_TX1, READ_TX1_BUSY,
        READ_TX2, READ_TX2_BUSY,
        READ_TX3, READ_TX3_BUSY,
        READ_TX4, READ_TX4_BUSY,

        FEAT_D0, FEAT_D1, FEAT_D2, FEAT_D3, FEAT_START,
        BATCH_D0, BATCH_D1, BATCH_D2, BATCH_D3, BATCH_START, BATCH_ACK,
        MODE_BYTE, LABEL_BYTE
    );

    signal st : cmd_state_t := WAIT_CMD;

    signal current_cmd     : std_logic_vector(7 downto 0) := (others => '0');
    signal pending_mem_sel : std_logic_vector(1 downto 0) := (others => '0');
    signal pending_addr    : std_logic_vector(15 downto 0) := (others => '0');
    signal pending_count   : unsigned(15 downto 0) := (others => '0');
    signal pending_data    : std_logic_vector(39 downto 0) := (others => '0');
    signal read_data_latch : std_logic_vector(39 downto 0) := (others => '0');

    signal tx_start_r : std_logic := '0';
    signal tx_data_r  : std_logic_vector(7 downto 0) := (others => '0');

    signal load_mode_r   : std_logic := '0';
    signal mem_sel_r     : std_logic_vector(1 downto 0) := (others => '0');
    signal mem_we_r      : std_logic := '0';
    signal mem_addr_r    : std_logic_vector(15 downto 0) := (others => '0');
    signal mem_data_in_r : std_logic_vector(39 downto 0) := (others => '0');

    signal feature_value_r : std_logic_vector(31 downto 0) := (others => '0');
    signal feature_valid_r : std_logic := '0';
    signal start_r         : std_logic := '0';
    signal train_mode_r    : std_logic := '0';
    signal finalize_r      : std_logic := '0';
    signal label_r         : std_logic_vector(2 downto 0) := (others => '0');

    signal feature_count    : integer range 0 to 31 := 0;
    signal done_prev        : std_logic := '0';
    signal tx_pending_done  : std_logic := '0';
    signal tx_pending_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal finalize_armed   : std_logic := '0';

begin

    tx_start_o <= tx_start_r;
    tx_data_o  <= tx_data_r;

    load_mode_o   <= load_mode_r;
    mem_sel_o     <= mem_sel_r;
    mem_we_o      <= mem_we_r;
    mem_addr_o    <= mem_addr_r;
    mem_data_in_o <= mem_data_in_r;

    feature_value_o <= feature_value_r;
    feature_valid_o <= feature_valid_r;
    start_o         <= start_r;
    train_mode_o    <= train_mode_r;
    finalize_o      <= finalize_r;
    label_o         <= label_r;

    process(clk)
    begin
        if rising_edge(clk) then
            tx_start_r     <= '0';
            mem_we_r       <= '0';
            feature_valid_r <= '0';
            start_r        <= '0';
            finalize_r     <= '0';
            load_mode_r    <= '0';

            if reset = '1' then
                st               <= WAIT_CMD;
                current_cmd      <= (others => '0');
                pending_mem_sel  <= (others => '0');
                pending_addr     <= (others => '0');
                pending_count    <= (others => '0');
                pending_data     <= (others => '0');
                read_data_latch  <= (others => '0');

                tx_data_r        <= (others => '0');

                load_mode_r      <= '0';
                mem_sel_r        <= (others => '0');
                mem_we_r         <= '0';
                mem_addr_r       <= (others => '0');
                mem_data_in_r    <= (others => '0');

                feature_value_r  <= (others => '0');
                feature_valid_r  <= '0';
                start_r          <= '0';
                train_mode_r     <= '0';
                finalize_r       <= '0';
                label_r          <= (others => '0');

                feature_count    <= 0;
                done_prev        <= '0';
                tx_pending_done  <= '0';
                tx_pending_data  <= (others => '0');
                finalize_armed   <= '0';

            else
                if done_i = '1' and done_prev = '0' then
                    tx_pending_done  <= '1';
                    if finalize_armed = '1' then
                        tx_pending_data <= FINALIZE_DONE_BYTE;
                        finalize_armed  <= '0';
                    else
                        tx_pending_data <= "00000" & recognized_class_i;
                    end if;
                end if;
                done_prev <= done_i;

                if tx_pending_done = '1' and tx_busy_i = '0' and st = WAIT_CMD then
                    tx_start_r      <= '1';
                    tx_data_r       <= tx_pending_data;
                    tx_pending_done <= '0';
                end if;

                case st is

                    when WAIT_CMD =>
                        if rx_valid_i = '1' then
                            current_cmd <= rx_byte_i;

                            case rx_byte_i is
                                when x"49" => -- 'I'
                                    pending_mem_sel <= "00";
                                    st <= WRITE_ADDR0;

                                when x"43" => -- 'C'
                                    pending_mem_sel <= "01";
                                    st <= WRITE_ADDR0;

                                when x"41" => -- 'A'
                                    pending_mem_sel <= "10";
                                    st <= WRITE_ADDR0;

                                when x"57" => -- 'W': block write, auto-incrementing address
                                    st <= WBULK_SEL;

                                when x"52" => -- 'R'
                                    st <= READ_SEL;

                                when x"46" => -- 'F'
                                    st <= FEAT_D0;

                                when x"42" => -- 'B'
                                    feature_count <= 0;
                                    st <= BATCH_D0;

                                when x"4d" => -- 'M'
                                    st <= MODE_BYTE;

                                when x"4c" => -- 'L'
                                    st <= LABEL_BYTE;

                                when x"58" => -- 'X': finalize current counters
                                    finalize_r <= '1';
                                    start_r    <= '1';
                                    finalize_armed <= '1';

                                    if tx_busy_i = '0' then
                                        tx_start_r <= '1';
                                        tx_data_r  <= ACK_BYTE;
                                    end if;

                                when x"53" => -- 'S': force start
                                    start_r <= '1';

                                    if tx_busy_i = '0' then
                                        tx_start_r <= '1';
                                        tx_data_r  <= ACK_BYTE;
                                    end if;

                                when others =>
                                    if tx_busy_i = '0' then
                                        tx_start_r <= '1';
                                        tx_data_r  <= x"45";
                                    end if;
                            end case;
                        end if;

                    ----------------------------------------------------------------
                    -- Memory write command:
                    -- 'I'/'C'/'A' + addr_lo + addr_hi + 5 data bytes
                    -- little endian: D0 = bits 7..0, D4 = bits 39..32
                    ----------------------------------------------------------------
                    when WRITE_ADDR0 =>
                        if rx_valid_i = '1' then
                            pending_addr(7 downto 0) <= rx_byte_i;
                            st <= WRITE_ADDR1;
                        end if;

                    when WRITE_ADDR1 =>
                        if rx_valid_i = '1' then
                            pending_addr(15 downto 8) <= rx_byte_i;
                            st <= WRITE_D0;
                        end if;

                    when WRITE_D0 =>
                        if rx_valid_i = '1' then
                            pending_data(7 downto 0) <= rx_byte_i;
                            st <= WRITE_D1;
                        end if;

                    when WRITE_D1 =>
                        if rx_valid_i = '1' then
                            pending_data(15 downto 8) <= rx_byte_i;
                            st <= WRITE_D2;
                        end if;

                    when WRITE_D2 =>
                        if rx_valid_i = '1' then
                            pending_data(23 downto 16) <= rx_byte_i;
                            st <= WRITE_D3;
                        end if;

                    when WRITE_D3 =>
                        if rx_valid_i = '1' then
                            pending_data(31 downto 24) <= rx_byte_i;
                            st <= WRITE_D4;
                        end if;

                    when WRITE_D4 =>
                        if rx_valid_i = '1' then
                            pending_data(39 downto 32) <= rx_byte_i;

                            load_mode_r   <= '1';
                            mem_sel_r     <= pending_mem_sel;
                            mem_addr_r    <= pending_addr;
                            mem_data_in_r <= rx_byte_i & pending_data(31 downto 0);
                            mem_we_r      <= '1';

                            if tx_busy_i = '0' then
                                tx_start_r <= '1';
                                tx_data_r  <= ACK_BYTE;
                            end if;

                            st <= WAIT_CMD;
                        end if;

                   when WBULK_SEL =>
                        if rx_valid_i = '1' then
                            case rx_byte_i is
                                when x"49" => pending_mem_sel <= "00";
                                when x"43" => pending_mem_sel <= "01";
                                when others => pending_mem_sel <= "10";
                            end case;
                            st <= WBULK_ADDR0;
                        end if;

                    when WBULK_ADDR0 =>
                        if rx_valid_i = '1' then
                            pending_addr(7 downto 0) <= rx_byte_i;
                            st <= WBULK_ADDR1;
                        end if;

                    when WBULK_ADDR1 =>
                        if rx_valid_i = '1' then
                            pending_addr(15 downto 8) <= rx_byte_i;
                            st <= WBULK_CNT0;
                        end if;

                    when WBULK_CNT0 =>
                        if rx_valid_i = '1' then
                            pending_count(7 downto 0) <= unsigned(rx_byte_i);
                            st <= WBULK_CNT1;
                        end if;

                    when WBULK_CNT1 =>
                        if rx_valid_i = '1' then
                            pending_count(15 downto 8) <= unsigned(rx_byte_i);
                            st <= WBULK_D0;
                        end if;

                    when WBULK_D0 =>
                        if rx_valid_i = '1' then
                            pending_data(7 downto 0) <= rx_byte_i;
                            st <= WBULK_D1;
                        end if;

                    when WBULK_D1 =>
                        if rx_valid_i = '1' then
                            pending_data(15 downto 8) <= rx_byte_i;
                            st <= WBULK_D2;
                        end if;

                    when WBULK_D2 =>
                        if rx_valid_i = '1' then
                            pending_data(23 downto 16) <= rx_byte_i;
                            st <= WBULK_D3;
                        end if;

                    when WBULK_D3 =>
                        if rx_valid_i = '1' then
                            pending_data(31 downto 24) <= rx_byte_i;
                            st <= WBULK_D4;
                        end if;

                    when WBULK_D4 =>
                        if rx_valid_i = '1' then
                            pending_data(39 downto 32) <= rx_byte_i;

                            load_mode_r   <= '1';
                            mem_sel_r     <= pending_mem_sel;
                            mem_addr_r    <= pending_addr;
                            mem_data_in_r <= rx_byte_i & pending_data(31 downto 0);
                            mem_we_r      <= '1';

                            if pending_count <= 1 then
                                st <= WBULK_ACK;
                            else
                                pending_addr  <= std_logic_vector(unsigned(pending_addr) + 1);
                                pending_count <= pending_count - 1;
                                st            <= WBULK_D0;
                            end if;
                        end if;

                    when WBULK_ACK =>
                        if tx_busy_i = '0' then
                            tx_start_r <= '1';
                            tx_data_r  <= ACK_BYTE;
                            st         <= WAIT_CMD;
                        end if;

                    when READ_SEL =>
                        if rx_valid_i = '1' then
                            case rx_byte_i is
                                when x"49" => pending_mem_sel <= "00";
                                when x"43" => pending_mem_sel <= "01";
                                when others => pending_mem_sel <= "10";
                            end case;

                            st <= READ_ADDR0;
                        end if;

                    when READ_ADDR0 =>
                        if rx_valid_i = '1' then
                            pending_addr(7 downto 0) <= rx_byte_i;
                            st <= READ_ADDR1;
                        end if;

                    when READ_ADDR1 =>
                        if rx_valid_i = '1' then
                            pending_addr(15 downto 8) <= rx_byte_i;

                            load_mode_r <= '1';
                            mem_sel_r   <= pending_mem_sel;
                            mem_addr_r  <= rx_byte_i & pending_addr(7 downto 0);

                            st <= READ_WAIT;
                        end if;

                    when READ_WAIT =>
                        load_mode_r <= '1';
                        mem_sel_r   <= pending_mem_sel;
                        mem_addr_r  <= pending_addr;
                        st <= READ_WAIT2;

                    when READ_WAIT2 =>
                        load_mode_r     <= '1';
                        mem_sel_r       <= pending_mem_sel;
                        mem_addr_r      <= pending_addr;
                        read_data_latch <= mem_data_out_i;
                        st <= READ_TX0;

                    when READ_TX0 =>
                        if tx_busy_i = '0' then
                            tx_start_r <= '1';
                            tx_data_r  <= read_data_latch(7 downto 0);
                            st <= READ_TX0_BUSY;
                        end if;

                    when READ_TX0_BUSY =>
                        if tx_busy_i = '1' then
                            st <= READ_TX1;
                        end if;

                    when READ_TX1 =>
                        if tx_busy_i = '0' then
                            tx_start_r <= '1';
                            tx_data_r  <= read_data_latch(15 downto 8);
                            st <= READ_TX1_BUSY;
                        end if;

                    when READ_TX1_BUSY =>
                        if tx_busy_i = '1' then
                            st <= READ_TX2;
                        end if;

                    when READ_TX2 =>
                        if tx_busy_i = '0' then
                            tx_start_r <= '1';
                            tx_data_r  <= read_data_latch(23 downto 16);
                            st <= READ_TX2_BUSY;
                        end if;

                    when READ_TX2_BUSY =>
                        if tx_busy_i = '1' then
                            st <= READ_TX3;
                        end if;

                    when READ_TX3 =>
                        if tx_busy_i = '0' then
                            tx_start_r <= '1';
                            tx_data_r  <= read_data_latch(31 downto 24);
                            st <= READ_TX3_BUSY;
                        end if;

                    when READ_TX3_BUSY =>
                        if tx_busy_i = '1' then
                            st <= READ_TX4;
                        end if;

                    when READ_TX4 =>
                        if tx_busy_i = '0' then
                            tx_start_r <= '1';
                            tx_data_r  <= read_data_latch(39 downto 32);
                            st <= READ_TX4_BUSY;
                        end if;

                    when READ_TX4_BUSY =>
                        if tx_busy_i = '1' then
                            st <= WAIT_CMD;
                        end if;

                    when FEAT_D0 =>
                        if rx_valid_i = '1' then
                            pending_data(7 downto 0) <= rx_byte_i;
                            st <= FEAT_D1;
                        end if;

                    when FEAT_D1 =>
                        if rx_valid_i = '1' then
                            pending_data(15 downto 8) <= rx_byte_i;
                            st <= FEAT_D2;
                        end if;

                    when FEAT_D2 =>
                        if rx_valid_i = '1' then
                            pending_data(23 downto 16) <= rx_byte_i;
                            st <= FEAT_D3;
                        end if;

                    when FEAT_D3 =>
                        if rx_valid_i = '1' then
                            feature_value_r <= rx_byte_i & pending_data(23 downto 0);
                            feature_valid_r <= '1';

                            if feature_count = 31 then
                                feature_count <= 0;
                                st            <= FEAT_START;
                            else
                                feature_count <= feature_count + 1;
                                st            <= WAIT_CMD;
                            end if;

                            if tx_busy_i = '0' then
                                tx_start_r <= '1';
                                tx_data_r  <= ACK_BYTE;
                            end if;
                        end if;

                    when FEAT_START =>
                        start_r <= '1';
                        st      <= WAIT_CMD;

                    ----------------------------------------------------------------
                    -- Batched feature write command:
                    -- 'B' + 32 * (4-byte feature value)
                    ----------------------------------------------------------------
                    when BATCH_D0 =>
                        if rx_valid_i = '1' then
                            pending_data(7 downto 0) <= rx_byte_i;
                            st <= BATCH_D1;
                        end if;

                    when BATCH_D1 =>
                        if rx_valid_i = '1' then
                            pending_data(15 downto 8) <= rx_byte_i;
                            st <= BATCH_D2;
                        end if;

                    when BATCH_D2 =>
                        if rx_valid_i = '1' then
                            pending_data(23 downto 16) <= rx_byte_i;
                            st <= BATCH_D3;
                        end if;

                    when BATCH_D3 =>
                        if rx_valid_i = '1' then
                            feature_value_r <= rx_byte_i & pending_data(23 downto 0);
                            feature_valid_r <= '1';

                            if feature_count = 31 then
                                feature_count <= 0;
                                st            <= BATCH_START;
                            else
                                feature_count <= feature_count + 1;
                                st            <= BATCH_D0;
                            end if;
                        end if;

                    when BATCH_START =>
                        start_r <= '1';
                        st      <= BATCH_ACK;

                    when BATCH_ACK =>
                        if tx_busy_i = '0' then
                            tx_start_r <= '1';
                            tx_data_r  <= ACK_BYTE;
                            st         <= WAIT_CMD;
                        end if;

                    when MODE_BYTE =>
                        if rx_valid_i = '1' then
                            train_mode_r <= rx_byte_i(0);

                            if tx_busy_i = '0' then
                                tx_start_r <= '1';
                                tx_data_r  <= ACK_BYTE;
                            end if;

                            st <= WAIT_CMD;
                        end if;

                    when LABEL_BYTE =>
                        if rx_valid_i = '1' then
                            label_r <= rx_byte_i(2 downto 0);

                            if tx_busy_i = '0' then
                                tx_start_r <= '1';
                                tx_data_r  <= ACK_BYTE;
                            end if;

                            st <= WAIT_CMD;
                        end if;

                end case;
            end if;
        end if;
    end process;

end rtl;
