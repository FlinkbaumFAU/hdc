library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Full-chip top for IHP SG13CMOS5L: sg13cmos5l IO pad ring around
-- hdc_word40_top. Pads are black boxes (extended identifiers keep the
-- cell/pin case through GHDL). Pad power pins (vdd/vss/iovdd/iovss) are
-- not modelled here; LibreLane connects them via PDN_MACRO_CONNECTIONS.
-- Instance names of all pads end in "_pad" (relied on by config.yaml).
entity hdc_chip_top is
    generic (
        G_CLK_FREQ_HZ : integer := 50_000_000;
        G_BAUD        : integer := 115200
    );
    port (
        pad_clk  : inout std_logic;
        pad_rstn : inout std_logic;
        pad_rxd  : inout std_logic;
        pad_txd  : inout std_logic;
        pad_led  : inout std_logic;
        -- Unused inputs: their IOPadIn cells only add gate area on the IO
        -- ring's vdd net (KLayout Ant.e on the ring rails; see config.yaml)
        pad_spare : inout std_logic_vector(7 downto 0)
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

    signal clk, rstn, rxd, txd, led : std_logic;

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
    rxd_pad:  \sg13cmos5l_IOPadIn\     port map (\pad\ => pad_rxd,  \p2c\ => rxd);
    txd_pad:  \sg13cmos5l_IOPadOut30mA\ port map (\pad\ => pad_txd,  \c2p\ => txd);
    led_pad:  \sg13cmos5l_IOPadOut30mA\ port map (\pad\ => pad_led,  \c2p\ => led);

    -- Spare inputs (p2c left open; kept by pad_keep.v)
    spare0_pad: \sg13cmos5l_IOPadIn\ port map (\pad\ => pad_spare(0), \p2c\ => open);
    spare1_pad: \sg13cmos5l_IOPadIn\ port map (\pad\ => pad_spare(1), \p2c\ => open);
    spare2_pad: \sg13cmos5l_IOPadIn\ port map (\pad\ => pad_spare(2), \p2c\ => open);
    spare3_pad: \sg13cmos5l_IOPadIn\ port map (\pad\ => pad_spare(3), \p2c\ => open);
    spare4_pad: \sg13cmos5l_IOPadIn\ port map (\pad\ => pad_spare(4), \p2c\ => open);
    spare5_pad: \sg13cmos5l_IOPadIn\ port map (\pad\ => pad_spare(5), \p2c\ => open);
    spare6_pad: \sg13cmos5l_IOPadIn\ port map (\pad\ => pad_spare(6), \p2c\ => open);
    spare7_pad: \sg13cmos5l_IOPadIn\ port map (\pad\ => pad_spare(7), \p2c\ => open);

    i_core: entity work.hdc_word40_top
        generic map (
            G_CLK_FREQ_HZ => G_CLK_FREQ_HZ,
            G_BAUD        => G_BAUD
        )
        port map (
            clk_i  => clk,
            rstn_i => rstn,
            led_o  => led,
            txd_o  => txd,
            rxd_i  => rxd
        );

end rtl;
