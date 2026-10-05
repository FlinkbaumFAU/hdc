library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

library fpga;
library asic;

-- Runs the Accelerator with the FPGA (inferred) memories and with the
-- SG13 SRAM-macro memories side by side on identical stimulus and checks
-- that done / recognized_class / read-back data match.
entity tb_mem_equiv is
    generic (
        G_D       : integer := 10000;
        G_SAMPLES : integer := 2      -- training samples per class
    );
end tb_mem_equiv;

architecture sim of tb_mem_equiv is
    constant N  : integer := 32;
    constant M  : integer := 40;
    constant K  : integer := 5;
    constant CH : integer := (G_D + 39) / 40;

    signal clk   : std_logic := '0';
    signal reset : std_logic := '1';
    signal stop  : boolean := false;

    signal feature_value : std_logic_vector(31 downto 0) := (others => '0');
    signal feature_valid, start, train_mode, finalize : std_logic := '0';
    signal label_in    : std_logic_vector(2 downto 0) := (others => '0');
    signal load_mode, mem_we : std_logic := '0';
    signal mem_sel     : std_logic_vector(1 downto 0) := "00";
    signal mem_addr    : std_logic_vector(15 downto 0) := (others => '0');
    signal mem_data_in : std_logic_vector(39 downto 0) := (others => '0');

    signal done_f, done_a : std_logic;
    signal cls_f, cls_a   : std_logic_vector(2 downto 0);
    signal dout_f, dout_a : std_logic_vector(39 downto 0);

    constant HV_LEN : std_logic_vector(13 downto 0) := std_logic_vector(to_unsigned(G_D, 14));
begin
    clk <= not clk after 5 ns when not stop;

    dut_f: entity fpga.Accelerator
        generic map (D => G_D, N => N, M => M, K => K, WORD_WIDTH => 40, SUPPORT_TRAINING => true)
        port map (clk => clk, reset => reset, done => done_f,
                  feature_value => feature_value, feature_valid => feature_valid, start => start,
                  train_mode => train_mode, finalize_training => finalize, label_in => label_in,
                  load_mode => load_mode, mem_sel => mem_sel, mem_we => mem_we, mem_addr => mem_addr,
                  mem_data_in => mem_data_in, hv_length => HV_LEN, mem_data_out => dout_f,
                  recognized_class => cls_f);

    dut_a: entity asic.Accelerator
        generic map (D => G_D, N => N, M => M, K => K, WORD_WIDTH => 40, SUPPORT_TRAINING => true)
        port map (clk => clk, reset => reset, done => done_a,
                  feature_value => feature_value, feature_valid => feature_valid, start => start,
                  train_mode => train_mode, finalize_training => finalize, label_in => label_in,
                  load_mode => load_mode, mem_sel => mem_sel, mem_we => mem_we, mem_addr => mem_addr,
                  mem_data_in => mem_data_in, hv_length => HV_LEN, mem_data_out => dout_a,
                  recognized_class => cls_a);

    -- Cycle-accurate comparison of the control outputs.
    check: process(clk)
    begin
        if rising_edge(clk) and reset = '0' then
            assert done_f = done_a
                report "done mismatch: fpga=" & std_logic'image(done_f) & " asic=" & std_logic'image(done_a)
                severity failure;
            if done_f = '1' then
                assert cls_f = cls_a report "recognized_class mismatch" severity failure;
            end if;
        end if;
    end process;

    stim: process
        variable s1, s2 : positive := 42;
        variable r      : real;
        variable errors : integer := 0;
        variable hits   : integer := 0;

        impure function rnd(bits : integer) return std_logic_vector is
            variable v : std_logic_vector(bits-1 downto 0);
        begin
            for i in v'range loop
                uniform(s1, s2, r);
                if r > 0.5 then v(i) := '1'; else v(i) := '0'; end if;
            end loop;
            return v;
        end function;

        procedure tick(n : integer := 1) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        procedure write_word(sel : std_logic_vector(1 downto 0); addr : integer;
                             data : std_logic_vector(39 downto 0)) is
        begin
            load_mode <= '1'; mem_sel <= sel; mem_we <= '1';
            mem_addr <= std_logic_vector(to_unsigned(addr, 16)); mem_data_in <= data;
            tick;
            load_mode <= '0'; mem_we <= '0';
        end procedure;

        -- Same timing as hdc_uart_loader: address held 2 cycles, then latch.
        procedure read_cmp(sel : std_logic_vector(1 downto 0); addr : integer) is
        begin
            load_mode <= '1'; mem_sel <= sel; mem_we <= '0';
            mem_addr <= std_logic_vector(to_unsigned(addr, 16));
            tick(2);
            assert dout_f = dout_a
                report "read mismatch sel=" & integer'image(to_integer(unsigned(sel)))
                     & " addr=" & integer'image(addr) severity failure;
            load_mode <= '0';
        end procedure;

        procedure wait_done is
        begin
            loop
                tick;
                exit when done_f = '1';
            end loop;
        end procedure;

        -- Features of class c: values clustered around a class-specific level.
        procedure run_sample(c : integer; train : std_logic) is
            variable base : integer;
            variable fv   : integer;
        begin
            train_mode <= train;
            label_in   <= std_logic_vector(to_unsigned(c, 3));
            base := 3000 + c * 6000;
            for i in 0 to N-1 loop
                uniform(s1, s2, r);
                fv := base + ((i * 997) mod 2000) + integer(r * 1500.0);
                feature_value <= std_logic_vector(to_unsigned(fv, 32));
                feature_valid <= '1';
                tick;
            end loop;
            feature_valid <= '0';
            start <= '1'; tick; start <= '0';
            wait_done;
        end procedure;

        procedure finalize_label(c : integer) is
        begin
            train_mode <= '1';
            label_in   <= std_logic_vector(to_unsigned(c, 3));
            finalize <= '1'; start <= '1'; tick;
            finalize <= '0'; start <= '0';
            wait_done;
        end procedure;
    begin
        tick(3);
        reset <= '0';
        tick(2);

        report "loading IM/CM";
        for a in 0 to N*CH-1 loop write_word("00", a, rnd(40)); end loop;
        for a in 0 to M*CH-1 loop write_word("01", a, rnd(40)); end loop;
        for a in 0 to K*CH-1 loop write_word("10", a, (others => '0')); end loop;

        report "read-back (spans all SRAM banks)";
        for i in 0 to 63 loop
            read_cmp("00", (i * 997) mod (N*CH));
            read_cmp("01", (i * 1543) mod (M*CH));
        end loop;
        read_cmp("00", N*CH-1);
        read_cmp("01", M*CH-1);

        -- SRAM content is undefined after power-up; the counters are only
        -- cleared at the end of a finalize. One dummy finalize clears them.
        report "clearing class counters (dummy finalize)";
        finalize_label(0);

        for c in 0 to K-1 loop
            report "training class " & integer'image(c);
            for s in 1 to G_SAMPLES loop
                run_sample(c, '1');
            end loop;
            finalize_label(c);
        end loop;

        report "AM read-back";
        for i in 0 to 63 loop
            read_cmp("10", (i * 211) mod (K*CH));
        end loop;

        report "testing";
        for c in 0 to K-1 loop
            for s in 1 to 2 loop
                run_sample(c, '0');
                if to_integer(unsigned(cls_f)) = c then hits := hits + 1; end if;
            end loop;
        end loop;

        report "PASS: FPGA and SRAM-macro memories behave identically ("
               & integer'image(hits) & "/" & integer'image(2*K) & " test samples classified correctly)";
        stop <= true;
        wait;
    end process;
end sim;
