library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Minimal synthesis top for measuring the word40 HDC accelerator without
-- UART RX/TX and without the UART bootloader/loader FSM.
entity hdc_word40_core_top is
    generic (
        G_D                : integer := 1000;
        G_M                : integer := 40;
        G_K                : integer := 5;
        G_SUPPORT_TRAINING : boolean := true
    );
    Port (
        clk_i  : in  STD_LOGIC;
        rstn_i : in  STD_LOGIC;
        led_o  : out STD_LOGIC
    );
end hdc_word40_core_top;

architecture Behavioral of hdc_word40_core_top is
    constant C_HV_LENGTH : std_logic_vector(13 downto 0) := std_logic_vector(to_unsigned(G_D, 14));

    signal reset   : std_logic;
    signal sys_clk : std_logic;

    signal drive_counter : unsigned(31 downto 0) := (others => '0');

    signal load_mode_sig    : std_logic;
    signal mem_sel_sig      : std_logic_vector(1 downto 0);
    signal mem_we_sig       : std_logic;
    signal mem_addr_sig     : std_logic_vector(15 downto 0);
    signal mem_data_in_sig  : std_logic_vector(39 downto 0);
    signal mem_data_out_sig : std_logic_vector(39 downto 0);

    signal feature_value_sig : std_logic_vector(31 downto 0);
    signal feature_valid_sig : std_logic;
    signal start_sig         : std_logic;
    signal train_mode_sig    : std_logic;
    signal finalize_sig      : std_logic;
    signal label_sig         : std_logic_vector(2 downto 0);

    signal done_sig             : std_logic;
    signal recognized_class_sig : std_logic_vector(2 downto 0);
begin
    reset <= not rstn_i;
    sys_clk <= clk_i;

    process(sys_clk)
    begin
        if rising_edge(sys_clk) then
            if reset = '1' then
                drive_counter <= (others => '0');
            else
                drive_counter <= drive_counter + 1;
            end if;
        end if;
    end process;

    feature_value_sig <= std_logic_vector(drive_counter);
    feature_valid_sig <= '1';
    start_sig         <= '1' when drive_counter(5 downto 0) = "000000" else '0';
    train_mode_sig    <= drive_counter(8);
    finalize_sig      <= '1' when drive_counter(11 downto 0) = x"800" else '0';
    label_sig         <= std_logic_vector(drive_counter(10 downto 8));

    load_mode_sig   <= drive_counter(12);
    mem_sel_sig     <= std_logic_vector(drive_counter(14 downto 13));
    mem_we_sig      <= drive_counter(15);
    mem_addr_sig    <= std_logic_vector(drive_counter(15 downto 0));
    mem_data_in_sig <= std_logic_vector(drive_counter) & std_logic_vector(drive_counter(7 downto 0));

    accel_unit: entity work.Accelerator
        generic map (
            D => G_D,
            N => 32,
            M => G_M,
            K => G_K,
            WORD_WIDTH => 40,
            SUPPORT_TRAINING => G_SUPPORT_TRAINING
        )
        port map (
            clk               => sys_clk,
            reset             => reset,
            done              => done_sig,
            feature_value     => feature_value_sig,
            feature_valid     => feature_valid_sig,
            start             => start_sig,
            train_mode        => train_mode_sig,
            finalize_training => finalize_sig,
            label_in          => label_sig,
            load_mode         => load_mode_sig,
            mem_sel           => mem_sel_sig,
            mem_we            => mem_we_sig,
            mem_addr          => mem_addr_sig,
            mem_data_in       => mem_data_in_sig,
            hv_length         => C_HV_LENGTH,
            mem_data_out      => mem_data_out_sig,
            recognized_class  => recognized_class_sig
        );

    led_o <= done_sig xor recognized_class_sig(0) xor mem_data_out_sig(0);
end Behavioral;
