library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Full-chip top for IHP SG13CMOS5L: sg13cmos5l IO pad ring around
-- hdc_word40_top. Pads are black boxes (extended identifiers keep the
-- cell/pin case through GHDL). Pad power pins (vdd/vss/iovdd/iovss) are
-- not modelled here; LibreLane connects them via PDN_MACRO_CONNECTIONS.
-- Instance names of all pads end in "_pad" (relied on by config.yaml).
entity hdc_chip_top is
    generic (
        G_CLK_FREQ_HZ : integer := 50_000_000  -- informational; CLOCK_PERIOD in config.yaml
    );
    port (
        pad_clk  : inout std_logic;
        pad_rstn : inout std_logic;
        pad_led  : inout std_logic;
        -- SPI slave (sclk/cs_n also clock flops in the SPI front end)
        pad_sclk : inout std_logic;
        pad_mosi : inout std_logic;
        pad_cs_n : inout std_logic;
        pad_miso : inout std_logic;
        -- Unused inputs: their IOPadIn cells only add gate area on the IO
        -- ring's vdd net (KLayout Ant.e on the ring rails; see config.yaml)
        pad_spare : inout std_logic_vector(4 downto 0)
    );
end hdc_chip_top;

architecture rtl of hdc_chip_top is

    component \sg13cmos5l_IOPadIn\ is
        port (
            \pad\ : inout std_logic;
            \p2c\ : out   std_logic
        );
    end component;

    component \sg13cmos5l_IOPadOut30mA\ is
        port (
            \pad\ : inout std_logic;
            \c2p\ : in    std_logic
        );
    end component;

    component \sg13cmos5l_IOPadVdd\ is end component;
    component \sg13cmos5l_IOPadVss\ is end component;
    component \sg13cmos5l_IOPadIOVdd\ is end component;
    component \sg13cmos5l_IOPadIOVss\ is end component;

    signal clk, rstn, led, sclk, mosi, cs_n, miso : std_logic;

begin

    -- Core supply. pdngen only straps the core ring to the pad ring on the
    -- east/west sides, so pairs 2/3 sit there; pairs 0/1 (north/south) only
    -- feed the IO ring rails.
    vdd0_pad:  \sg13cmos5l_IOPadVdd\;
    vdd1_pad:  \sg13cmos5l_IOPadVdd\;
    vdd2_pad:  \sg13cmos5l_IOPadVdd\;
    vdd3_pad:  \sg13cmos5l_IOPadVdd\;
    vss0_pad:  \sg13cmos5l_IOPadVss\;
    vss1_pad:  \sg13cmos5l_IOPadVss\;
    vss2_pad:  \sg13cmos5l_IOPadVss\;
    vss3_pad:  \sg13cmos5l_IOPadVss\;
    iovdd_pad: \sg13cmos5l_IOPadIOVdd\;
    iovss_pad: \sg13cmos5l_IOPadIOVss\;

    clk_pad:  \sg13cmos5l_IOPadIn\     port map (\pad\ => pad_clk,  \p2c\ => clk);
    rstn_pad: \sg13cmos5l_IOPadIn\     port map (\pad\ => pad_rstn, \p2c\ => rstn);
    sclk_pad: \sg13cmos5l_IOPadIn\     port map (\pad\ => pad_sclk, \p2c\ => sclk);
    mosi_pad: \sg13cmos5l_IOPadIn\     port map (\pad\ => pad_mosi, \p2c\ => mosi);
    cs_n_pad: \sg13cmos5l_IOPadIn\     port map (\pad\ => pad_cs_n, \p2c\ => cs_n);
    miso_pad: \sg13cmos5l_IOPadOut30mA\ port map (\pad\ => pad_miso, \c2p\ => miso);
    led_pad:  \sg13cmos5l_IOPadOut30mA\ port map (\pad\ => pad_led,  \c2p\ => led);

    -- Spare inputs (p2c left open; kept by pad_keep.v)
    spare0_pad: \sg13cmos5l_IOPadIn\ port map (\pad\ => pad_spare(0), \p2c\ => open);
    spare1_pad: \sg13cmos5l_IOPadIn\ port map (\pad\ => pad_spare(1), \p2c\ => open);
    spare2_pad: \sg13cmos5l_IOPadIn\ port map (\pad\ => pad_spare(2), \p2c\ => open);
    spare3_pad: \sg13cmos5l_IOPadIn\ port map (\pad\ => pad_spare(3), \p2c\ => open);
    spare4_pad: \sg13cmos5l_IOPadIn\ port map (\pad\ => pad_spare(4), \p2c\ => open);

    i_core: entity work.hdc_word40_top
        generic map (
            G_D           => 1000,
            G_CLK_FREQ_HZ => G_CLK_FREQ_HZ,
            G_USE_PLL     => false  -- GateMate CC_PLL, FPGA only
        )
        port map (
            clk_i  => clk,
            rstn_i => rstn,
            led_o  => led,
            sclk_i => sclk,
            mosi_i => mosi,
            miso_o => miso,
            cs_n_i => cs_n
        );

end rtl;
