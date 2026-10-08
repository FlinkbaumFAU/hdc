library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Feature commands remain 32-bit / 4 bytes.
entity hdc_word40_top is
    generic (
        G_D                : integer := 1000;
        G_M                : integer := 40;
        G_K                : integer := 5;
        G_SUPPORT_TRAINING : boolean := true;
        G_CLK_FREQ_HZ      : integer := 30_000_000;
        G_USE_PLL          : boolean := false
    );
    Port (
        clk_i  : in  STD_LOGIC;
        rstn_i : in  STD_LOGIC;
        led_o  : out STD_LOGIC;

        -- SPI-style command/data link.
        sclk_i : in  STD_LOGIC;
        mosi_i : in  STD_LOGIC;
        miso_o : out STD_LOGIC;
        cs_n_i : in  STD_LOGIC
    );
end hdc_word40_top;

architecture Behavioral of hdc_word40_top is
    component CC_PLL is
        generic (
            REF_CLK         : string;
            OUT_CLK         : string;
            PERF_MD         : string;
            LOW_JITTER      : integer;
            CI_FILTER_CONST : integer;
            CP_FILTER_CONST : integer
        );
        port (
            CLK_REF             : in  std_logic;
            USR_CLK_REF         : in  std_logic;
            CLK_FEEDBACK        : in  std_logic;
            USR_LOCKED_STDY_RST : in  std_logic;
            USR_PLL_LOCKED_STDY : out std_logic;
            USR_PLL_LOCKED      : out std_logic;
            CLK0                : out std_logic;
            CLK90               : out std_logic;
            CLK180              : out std_logic;
            CLK270              : out std_logic;
            CLK_REF_OUT         : out std_logic
        );
    end component;

    constant C_HV_LENGTH : std_logic_vector(13 downto 0) := std_logic_vector(to_unsigned(G_D, 14));

    signal reset      : std_logic;
    signal pll_reset  : std_logic;
    signal pll_locked : std_logic := '1';
    signal sys_clk    : std_logic;

    signal rx_byte  : std_logic_vector(7 downto 0);
    signal rx_valid : std_logic;
    signal tx_start : std_logic;
    signal tx_data  : std_logic_vector(7 downto 0);
    signal tx_busy  : std_logic;

    signal load_mode_sig      : std_logic;
    signal mem_sel_sig        : std_logic_vector(1 downto 0);
    signal mem_we_sig         : std_logic;
    signal mem_addr_sig       : std_logic_vector(15 downto 0);
    signal mem_data_in_sig    : std_logic_vector(39 downto 0);
    signal mem_data_out_sig   : std_logic_vector(39 downto 0);

    signal feature_value_sig  : std_logic_vector(31 downto 0);
    signal feature_valid_sig  : std_logic;
    signal start_sig          : std_logic;
    signal train_mode_sig     : std_logic;
    signal finalize_sig       : std_logic;
    signal label_sig          : std_logic_vector(2 downto 0);

    signal done_sig             : std_logic;
    signal recognized_class_sig : std_logic_vector(2 downto 0);
begin
    pll_reset <= '1' when G_USE_PLL and pll_locked = '0' else '0';
    reset <= (not rstn_i) or pll_reset;

    gen_pll : if G_USE_PLL generate
        u_pll : CC_PLL
            generic map (
                REF_CLK         => "10.0",
                OUT_CLK         => "30.0",
                PERF_MD         => "SPEED",
                LOW_JITTER      => 1,
                CI_FILTER_CONST => 2,
                CP_FILTER_CONST => 4
            )
            port map (
                CLK_REF             => clk_i,
                USR_CLK_REF         => '0',
                CLK_FEEDBACK        => '0',
                USR_LOCKED_STDY_RST => '0',
                USR_PLL_LOCKED_STDY => open,
                USR_PLL_LOCKED      => pll_locked,
                CLK0                => sys_clk,
                CLK90               => open,
                CLK180              => open,
                CLK270              => open,
                CLK_REF_OUT         => open
            );
    end generate;

    gen_no_pll : if not G_USE_PLL generate
    begin
        pll_locked <= '1';
        sys_clk    <= clk_i;
    end generate;

    u_spi: entity work.hdc_spi_loader
        port map (
            clk        => sys_clk,
            reset      => reset,
            rx_byte_o  => rx_byte,
            rx_valid_o => rx_valid,
            tx_start_i => tx_start,
            tx_data_i  => tx_data,
            tx_busy_o  => tx_busy,
            sclk_i     => sclk_i,
            mosi_i     => mosi_i,
            miso_o     => miso_o,
            cs_n_i     => cs_n_i
        );

    u_loader: entity work.hdc_cmd_loader
        port map (
            clk                => sys_clk,
            reset              => reset,
            rx_byte_i          => rx_byte,
            rx_valid_i         => rx_valid,
            tx_start_o         => tx_start,
            tx_data_o          => tx_data,
            tx_busy_i          => tx_busy,
            load_mode_o        => load_mode_sig,
            mem_sel_o          => mem_sel_sig,
            mem_we_o           => mem_we_sig,
            mem_addr_o         => mem_addr_sig,
            mem_data_in_o      => mem_data_in_sig,
            feature_value_o    => feature_value_sig,
            feature_valid_o    => feature_valid_sig,
            start_o            => start_sig,
            train_mode_o       => train_mode_sig,
            finalize_o         => finalize_sig,
            label_o            => label_sig,
            done_i             => done_sig,
            recognized_class_i => recognized_class_sig,
            mem_data_out_i     => mem_data_out_sig
        );

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

    led_o <= done_sig;
end Behavioral;
