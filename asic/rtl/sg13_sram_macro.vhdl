library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Thin wrapper around the IHP SG13 single-port SRAM macros (black boxes).
-- Selects the macro by name; BIST is disabled, bit mask fully enabled,
-- A_DLY tied high as required by the macro.
-- Read latency: 1 cycle. Output holds its value on write / idle cycles.
entity sg13_sram_macro is
    generic (
        MACRO : string;   -- e.g. "2048x32"
        ABITS : integer;
        DBITS : integer
    );
    port (
        clk  : in  std_logic;
        men  : in  std_logic;
        wen  : in  std_logic;
        ren  : in  std_logic;
        addr : in  std_logic_vector(ABITS-1 downto 0);
        din  : in  std_logic_vector(DBITS-1 downto 0);
        dout : out std_logic_vector(DBITS-1 downto 0)
    );
end sg13_sram_macro;

architecture rtl of sg13_sram_macro is

    -- Extended identifiers keep the case of the macro and pin names,
    -- otherwise GHDL lowercases them and they no longer match the LEF/LIB.
    component \RM_IHPSG13_1P_2048x32_c2_bm_bist\ is
        port (
            \A_CLK\, \A_MEN\, \A_WEN\, \A_REN\, \A_DLY\ : in std_logic;
            \A_ADDR\        : in  std_logic_vector(10 downto 0);
            \A_DIN\, \A_BM\ : in  std_logic_vector(31 downto 0);
            \A_DOUT\        : out std_logic_vector(31 downto 0);
            \A_BIST_CLK\, \A_BIST_EN\, \A_BIST_MEN\, \A_BIST_WEN\, \A_BIST_REN\ : in std_logic;
            \A_BIST_ADDR\   : in  std_logic_vector(10 downto 0);
            \A_BIST_DIN\, \A_BIST_BM\ : in std_logic_vector(31 downto 0)
        );
    end component;

    component \RM_IHPSG13_1P_4096x8_c3_bm_bist\ is
        port (
            \A_CLK\, \A_MEN\, \A_WEN\, \A_REN\, \A_DLY\ : in std_logic;
            \A_ADDR\        : in  std_logic_vector(11 downto 0);
            \A_DIN\, \A_BM\ : in  std_logic_vector(7 downto 0);
            \A_DOUT\        : out std_logic_vector(7 downto 0);
            \A_BIST_CLK\, \A_BIST_EN\, \A_BIST_MEN\, \A_BIST_WEN\, \A_BIST_REN\ : in std_logic;
            \A_BIST_ADDR\   : in  std_logic_vector(11 downto 0);
            \A_BIST_DIN\, \A_BIST_BM\ : in std_logic_vector(7 downto 0)
        );
    end component;

    component \RM_IHPSG13_1P_4096x16_c3_bm_bist\ is
        port (
            \A_CLK\, \A_MEN\, \A_WEN\, \A_REN\, \A_DLY\ : in std_logic;
            \A_ADDR\        : in  std_logic_vector(11 downto 0);
            \A_DIN\, \A_BM\ : in  std_logic_vector(15 downto 0);
            \A_DOUT\        : out std_logic_vector(15 downto 0);
            \A_BIST_CLK\, \A_BIST_EN\, \A_BIST_MEN\, \A_BIST_WEN\, \A_BIST_REN\ : in std_logic;
            \A_BIST_ADDR\   : in  std_logic_vector(11 downto 0);
            \A_BIST_DIN\, \A_BIST_BM\ : in std_logic_vector(15 downto 0)
        );
    end component;

    component \RM_IHPSG13_1P_256x48_c2_bm_bist\ is
        port (
            \A_CLK\, \A_MEN\, \A_WEN\, \A_REN\, \A_DLY\ : in std_logic;
            \A_ADDR\        : in  std_logic_vector(7 downto 0);
            \A_DIN\, \A_BM\ : in  std_logic_vector(47 downto 0);
            \A_DOUT\        : out std_logic_vector(47 downto 0);
            \A_BIST_CLK\, \A_BIST_EN\, \A_BIST_MEN\, \A_BIST_WEN\, \A_BIST_REN\ : in std_logic;
            \A_BIST_ADDR\   : in  std_logic_vector(7 downto 0);
            \A_BIST_DIN\, \A_BIST_BM\ : in std_logic_vector(47 downto 0)
        );
    end component;

    constant ONES   : std_logic_vector(DBITS-1 downto 0) := (others => '1');
    constant ZEROS  : std_logic_vector(DBITS-1 downto 0) := (others => '0');
    constant AZEROS : std_logic_vector(ABITS-1 downto 0) := (others => '0');

begin

    g_2048x32: if MACRO = "2048x32" generate
        assert ABITS = 11 and DBITS = 32 severity failure;
        u_mem: \RM_IHPSG13_1P_2048x32_c2_bm_bist\
            port map (
                \A_CLK\ => clk, \A_MEN\ => men, \A_WEN\ => wen, \A_REN\ => ren, \A_DLY\ => '1',
                \A_ADDR\ => addr, \A_DIN\ => din, \A_BM\ => ONES, \A_DOUT\ => dout,
                \A_BIST_CLK\ => '0', \A_BIST_EN\ => '0', \A_BIST_MEN\ => '0',
                \A_BIST_WEN\ => '0', \A_BIST_REN\ => '0',
                \A_BIST_ADDR\ => AZEROS, \A_BIST_DIN\ => ZEROS, \A_BIST_BM\ => ZEROS
            );
    end generate;

    g_4096x8: if MACRO = "4096x8" generate
        assert ABITS = 12 and DBITS = 8 severity failure;
        u_mem: \RM_IHPSG13_1P_4096x8_c3_bm_bist\
            port map (
                \A_CLK\ => clk, \A_MEN\ => men, \A_WEN\ => wen, \A_REN\ => ren, \A_DLY\ => '1',
                \A_ADDR\ => addr, \A_DIN\ => din, \A_BM\ => ONES, \A_DOUT\ => dout,
                \A_BIST_CLK\ => '0', \A_BIST_EN\ => '0', \A_BIST_MEN\ => '0',
                \A_BIST_WEN\ => '0', \A_BIST_REN\ => '0',
                \A_BIST_ADDR\ => AZEROS, \A_BIST_DIN\ => ZEROS, \A_BIST_BM\ => ZEROS
            );
    end generate;

    g_4096x16: if MACRO = "4096x16" generate
        assert ABITS = 12 and DBITS = 16 severity failure;
        u_mem: \RM_IHPSG13_1P_4096x16_c3_bm_bist\
            port map (
                \A_CLK\ => clk, \A_MEN\ => men, \A_WEN\ => wen, \A_REN\ => ren, \A_DLY\ => '1',
                \A_ADDR\ => addr, \A_DIN\ => din, \A_BM\ => ONES, \A_DOUT\ => dout,
                \A_BIST_CLK\ => '0', \A_BIST_EN\ => '0', \A_BIST_MEN\ => '0',
                \A_BIST_WEN\ => '0', \A_BIST_REN\ => '0',
                \A_BIST_ADDR\ => AZEROS, \A_BIST_DIN\ => ZEROS, \A_BIST_BM\ => ZEROS
            );
    end generate;

    g_256x48: if MACRO = "256x48" generate
        assert ABITS = 8 and DBITS = 48 severity failure;
        u_mem: \RM_IHPSG13_1P_256x48_c2_bm_bist\
            port map (
                \A_CLK\ => clk, \A_MEN\ => men, \A_WEN\ => wen, \A_REN\ => ren, \A_DLY\ => '1',
                \A_ADDR\ => addr, \A_DIN\ => din, \A_BM\ => ONES, \A_DOUT\ => dout,
                \A_BIST_CLK\ => '0', \A_BIST_EN\ => '0', \A_BIST_MEN\ => '0',
                \A_BIST_WEN\ => '0', \A_BIST_REN\ => '0',
                \A_BIST_ADDR\ => AZEROS, \A_BIST_DIN\ => ZEROS, \A_BIST_BM\ => ZEROS
            );
    end generate;

end rtl;
