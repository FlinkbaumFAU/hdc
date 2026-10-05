library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Accelerator is
    generic (
        D : integer := 2000;
        N : integer := 32;
        M : integer := 40;
        K : integer := 5;
        WORD_WIDTH : integer := 40;
        SUPPORT_TRAINING : boolean := true
    );
    Port (
        clk   : in  STD_LOGIC;
        reset : in  STD_LOGIC;

        -- Top-Level Handshake
        done  : out STD_LOGIC;

        -- Feature-Input (32 Features pro Sample)
        feature_value : in STD_LOGIC_VECTOR(31 downto 0);
        feature_valid : in STD_LOGIC;
        start         : in STD_LOGIC;

        -- Training / Testing Steuerung
        train_mode        : in STD_LOGIC;                 -- '1' = Training, '0' = Testing
        finalize_training : in STD_LOGIC;                 -- '1' + start = Finalisierung (AM aus Countern beschreiben)
        label_in          : in STD_LOGIC_VECTOR(2 downto 0); -- Ground-Truth Label 0..K-1

        -- Externes Memory-Load-Interface (load_mode=1)
        load_mode   : in  STD_LOGIC;
        mem_sel     : in  STD_LOGIC_VECTOR(1 downto 0);   -- "00"=IM, "01"=CM, "10"=AM
        mem_we      : in  STD_LOGIC;
        mem_addr    : in  STD_LOGIC_VECTOR(15 downto 0);
        mem_data_in : in  STD_LOGIC_VECTOR(WORD_WIDTH-1 downto 0);
        hv_length   : in  STD_LOGIC_VECTOR(13 downto 0);
        mem_data_out: out STD_LOGIC_VECTOR(WORD_WIDTH-1 downto 0);

        -- Ergebnis im Testmodus
        recognized_class : out std_logic_vector(2 downto 0)
    );
end Accelerator;

architecture Behavioral of Accelerator is
    subtype dist_word_t is unsigned(15 downto 0);
    subtype pop_word_t is unsigned(6 downto 0);
    subtype pop4_t is unsigned(3 downto 0);
    constant CHUNK_WIDTH    : integer := WORD_WIDTH;

    --------------------------------------------------------------------
    -- Popcount for one 40-bit memory word. Written as a nibble tree to
    -- avoid a long c := c + 1 carry chain.
    --------------------------------------------------------------------
    function popcount4(x : std_logic_vector(3 downto 0)) return unsigned is
        variable c : unsigned(2 downto 0) := (others => '0');
    begin
        for i in x'range loop
            if x(i) = '1' then
                c := c + 1;
            end if;
        end loop;
        return c;
    end function;

    function popcount_word(x : std_logic_vector(39 downto 0)) return pop_word_t is
        variable p0, p1, p2, p3, p4 : unsigned(4 downto 0);
        variable s0, s1, s2         : unsigned(5 downto 0);
        variable total              : pop_word_t := (others => '0');
    begin
        p0 := resize(popcount4(x(3 downto 0)), 5)
            + resize(popcount4(x(7 downto 4)), 5);

        p1 := resize(popcount4(x(11 downto 8)), 5)
            + resize(popcount4(x(15 downto 12)), 5);

        p2 := resize(popcount4(x(19 downto 16)), 5)
            + resize(popcount4(x(23 downto 20)), 5);

        p3 := resize(popcount4(x(27 downto 24)), 5)
            + resize(popcount4(x(31 downto 28)), 5);

        p4 := resize(popcount4(x(35 downto 32)), 5)
            + resize(popcount4(x(39 downto 36)), 5);

        s0 := resize(p0, 6) + resize(p1, 6);
        s1 := resize(p2, 6) + resize(p3, 6);
        s2 := resize(p4, 6);

        total := resize(s0, 7) + resize(s1, 7) + resize(s2, 7);
        return total;
    end function;

    function level_from_feature(feature : std_logic_vector(31 downto 0)) return integer is
        variable fv  : unsigned(31 downto 0);
        variable lvl : integer;
    begin
        fv := unsigned(feature);
        lvl := (to_integer(fv) * (M - 1) + 16384) / 32768;

        if lvl < 0 then
            lvl := 0;
        elsif lvl > M-1 then
            lvl := M-1;
        end if;

        return lvl;
    end function;

    --------------------------------------------------------------------
    -- Memory components (synchron, 1-cycle read)
    --------------------------------------------------------------------
    component IdentityMemory
        generic (
            D : integer := 10016;
            N : integer := 32;
            WORD_WIDTH : integer := 64
        );
        Port (
            clk      : in STD_LOGIC;
            we       : in STD_LOGIC;
            addr     : in STD_LOGIC_VECTOR(15 downto 0);
            data_in  : in STD_LOGIC_VECTOR(WORD_WIDTH-1 downto 0);
            data_out : out STD_LOGIC_VECTOR(WORD_WIDTH-1 downto 0)
        );
    end component;

    component ContinousMemory
        generic (
            D : integer := 10016;
            M : integer := 40;
            WORD_WIDTH : integer := 64
        );
        Port (
            clk      : in STD_LOGIC;
            we       : in STD_LOGIC;
            addr     : in STD_LOGIC_VECTOR(15 downto 0);
            data_in  : in STD_LOGIC_VECTOR(WORD_WIDTH-1 downto 0);
            data_out : out STD_LOGIC_VECTOR(WORD_WIDTH-1 downto 0)
        );
    end component;

    component AssociativeMemory
        generic (
            D : integer := 10016;
            K : integer := 5;
            WORD_WIDTH : integer := 64
        );
        Port (
            clk      : in  STD_LOGIC;
            we       : in  STD_LOGIC;
            addr     : in  STD_LOGIC_VECTOR(15 downto 0);
            data_in  : in  STD_LOGIC_VECTOR(WORD_WIDTH-1 downto 0);
            data_out : out STD_LOGIC_VECTOR(WORD_WIDTH-1 downto 0)
        );
    end component;

    -- ClassCounter RAM (ausgelagerte Counter)
    component ClassCounterRAM is
        generic (
            DEPTH : integer := 50080; -- K * CHUNKS_PER_VEC * 32
            WIDTH : integer := 11      -- bit_counter_t Breite
        );
        Port (
            clk      : in  STD_LOGIC;
            we       : in  STD_LOGIC;
            addr     : in  STD_LOGIC_VECTOR(15 downto 0);
            data_in  : in  STD_LOGIC_VECTOR(WIDTH-1 downto 0);
            data_out : out STD_LOGIC_VECTOR(WIDTH-1 downto 0)
        );
    end component;

    --------------------------------------------------------------------
    -- Constants / Types
    --------------------------------------------------------------------
    
    -- Anzahl WORD_WIDTH-Bit-Chunks pro Vektor (bei WORD_WIDTH=40: D/40 Chunks)
    constant CHUNKS_PER_VEC : integer := (D + CHUNK_WIDTH - 1) / CHUNK_WIDTH;
    constant A              : integer := K;   -- Anzahl Klassen;
    constant COUNTER_BLOCK_SIZE : integer := CHUNKS_PER_VEC * CHUNK_WIDTH; -- Bits pro Klasse

    type ram_array_type      is array(0 to CHUNKS_PER_VEC-1) of std_logic_vector(CHUNK_WIDTH-1 downto 0);
    type counter_array_type  is array(0 to CHUNK_WIDTH-1) of unsigned(5 downto 0);
    type dist_array_type     is array(0 to A-1) of dist_word_t;
    type feature_array_t     is array(0 to N-1) of std_logic_vector(31 downto 0);

    -- Signed Counter für ein einzelnes Bit
    subtype bit_counter_t is signed(10 downto 0); -- Breite WIDTH=11

    --------------------------------------------------------------------
    -- State encoding
    --------------------------------------------------------------------
    type state_t is (
        S_IDLE,
        S_ENC_ADDR,
        S_ENC_WAIT,
        S_ENC_ACC,
        S_WRITE_MAJ,
        S_TRAIN_ACC,     -- Majority-HV eines Samples in Klassen-Counter akkumulieren (BRAM)
        S_FINAL_INIT,    -- Finalisierung: Adressen initialisieren
        S_FINAL_WRITE,   -- Finalisierung: Majority aus Countern in AM schreiben
        S_CLEAR_COUNTERS, -- 1-class counter RAM nach Finalisierung löschen
        S_COMPARE        -- Testing: Hamming-Distanz mit AM
    );
    signal state : state_t := S_IDLE;

    --------------------------------------------------------------------
    -- Signals
    --------------------------------------------------------------------
    signal feature_index : integer range 0 to N-1 := 0;
    signal chunk_counter : integer range 0 to CHUNKS_PER_VEC-1 := 0;

    -- Addr/WE + MUXing
    signal im_addr, cm_addr        : std_logic_vector(15 downto 0) := (others => '0');
    signal am_addr_external        : std_logic_vector(15 downto 0) := (others => '0');
    signal am_addr_internal        : std_logic_vector(15 downto 0) := (others => '0');
    signal am_addr                 : std_logic_vector(15 downto 0) := (others => '0');
    signal im_addr_mux, cm_addr_mux, am_addr_mux : std_logic_vector(15 downto 0);

    signal im_data, cm_data, am_data             : std_logic_vector(CHUNK_WIDTH-1 downto 0);
    signal im_data_in, cm_data_in                : std_logic_vector(CHUNK_WIDTH-1 downto 0);
    signal am_data_in_ext, am_data_in_core       : std_logic_vector(CHUNK_WIDTH-1 downto 0);
    signal am_data_in_mux                        : std_logic_vector(CHUNK_WIDTH-1 downto 0);
    signal im_data_out, cm_data_out, am_data_out : std_logic_vector(CHUNK_WIDTH-1 downto 0);

    signal im_we, cm_we          : std_logic;
    signal am_we_ext, am_we_core : std_logic := '0';
    signal am_we_mux             : std_logic;

    -- Feature buffer
    signal feature_values      : feature_array_t := (others => (others => '0'));
    signal feature_load_index  : integer range 0 to N := 0;
    signal features_ready      : STD_LOGIC := '0';

    -- Majority result eines Samples (MajorityRAM)
    signal maj_we           : std_logic := '0';
    signal maj_wr_addr      : integer range 0 to CHUNKS_PER_VEC-1 := 0;
    signal maj_rd_addr      : integer range 0 to CHUNKS_PER_VEC-1 := 0;
    signal maj_din          : std_logic_vector(CHUNK_WIDTH-1 downto 0) := (others => '0');
    signal maj_dout         : std_logic_vector(CHUNK_WIDTH-1 downto 0) := (others => '0');

    -- Compare FSM (Testing)
    signal comp_state   : integer range 0 to 10 := 0;
    signal class_idx    : integer range 0 to A-1 := 0;
    signal comp_chunk   : integer range 0 to CHUNKS_PER_VEC-1 := 0;
    signal dist_acc     : dist_word_t := (others => '0');
    signal distances    : dist_array_type := (others => (others => '0'));
    signal comp_xor_reg : std_logic_vector(CHUNK_WIDTH-1 downto 0) := (others => '0');
    signal comp_pop_reg : pop_word_t := (others => '0');
    signal best_dist    : dist_word_t := (others => '0');
    signal best_class   : integer range 0 to A-1 := 0;

    -- Training / Finalisierung Indizes
    signal train_class : integer range 0 to K-1 := 0;
    signal train_chunk : integer range 0 to CHUNKS_PER_VEC-1 := 0;

    signal final_class : integer range 0 to K-1 := 0;
    signal final_chunk : integer range 0 to CHUNKS_PER_VEC-1 := 0;

    -- Level indexing
    signal level_index_next : integer range 0 to M-1 := 0;

    -- Active chunks for the current build. The GateMate top uses the full
    -- vector length, so we keep this constant to avoid GHDL synthesis issues
    -- around integer arithmetic derived from hv_length.
    constant ACTIVE_CHUNKS : integer := CHUNKS_PER_VEC;

    --------------------------------------------------------------------
    -- ClassCounterRAM Interface + Mikro-FSMs
    --------------------------------------------------------------------
    signal cc_we    : std_logic := '0';
    signal cc_addr  : std_logic_vector(15 downto 0) := (others => '0');
    signal cc_din   : std_logic_vector(10 downto 0) := (others => '0'); -- WIDTH=11
    signal cc_dout  : std_logic_vector(10 downto 0) := (others => '0');

    -- Training: bitweises Update (3 Phasen wegen registrierter Adresse im RAM)
    signal train_bit    : integer range 0 to CHUNK_WIDTH-1 := 0;
    signal train_phase  : integer range 0 to 2 := 0; -- 0=Addr, 1=Wait, 2=Use/Write

    -- Finalisierung: bitweises Lesen & Majority-Bildung (3 Phasen)
    signal final_bit    : integer range 0 to CHUNK_WIDTH-1 := 0;
    signal final_phase  : integer range 0 to 2 := 0; -- 0=Addr, 1=Wait, 2=Use
    signal word_out_reg : std_logic_vector(CHUNK_WIDTH-1 downto 0) := (others => '0');

    -- Clear pointer for the one-class ClassCounterRAM. Range includes
    -- COUNTER_BLOCK_SIZE to keep arithmetic safe in synthesis.
    signal clear_index  : integer range 0 to COUNTER_BLOCK_SIZE := 0;

begin

    --------------------------------------------------------------------
    -- Externer Load-Pfad (IM / CM / AM)
    --------------------------------------------------------------------
    im_we   <= mem_we when (mem_sel = "00" and load_mode = '1') else '0';
    cm_we   <= mem_we when (mem_sel = "01" and load_mode = '1') else '0';
    am_we_ext <= mem_we when (mem_sel = "10" and load_mode = '1') else '0';

    im_addr <= mem_addr when mem_sel = "00" else (others => '0');
    cm_addr <= mem_addr when mem_sel = "01" else (others => '0');

    am_addr_external <= mem_addr when mem_sel = "10" else (others => '0');

    -- AM-Adress-MUX: extern (load_mode=1) oder intern (Compare / Finalisierung)
    am_addr <= am_addr_external when load_mode='1'
               else am_addr_internal;

    im_data_in    <= mem_data_in;
    cm_data_in    <= mem_data_in;
    am_data_in_ext <= mem_data_in;

    -- AM Write Enable: extern OR intern
    am_we_mux <= am_we_ext or am_we_core;

    -- AM Data-In: extern im Load-Mode, sonst intern aus Finalisierung
    am_data_in_mux <= am_data_in_ext when load_mode='1' else am_data_in_core;

    -- Rückgabe der Daten im Load-Mode
    with mem_sel select
        mem_data_out <= im_data_out when "00",
                        cm_data_out when "01",
                        am_data_out when "10",
                        (others => '0') when others;

    im_data_out <= im_data when load_mode = '1' else (others => '0');
    cm_data_out <= cm_data when load_mode = '1' else (others => '0');
    am_data_out <= am_data when load_mode = '1' else (others => '0');

    --------------------------------------------------------------------
    -- Memory Instanzen
    --------------------------------------------------------------------
    IM: IdentityMemory
        generic map (D => D, N => N, WORD_WIDTH => CHUNK_WIDTH)
        port map (
            clk      => clk,
            we       => im_we,
            addr     => im_addr_mux,
            data_in  => im_data_in,
            data_out => im_data
        );

    CIM: ContinousMemory
        generic map (D => D, M => M, WORD_WIDTH => CHUNK_WIDTH)
        port map (
            clk      => clk, 
            we       => cm_we, 
            addr     => cm_addr_mux, 
            data_in  => cm_data_in, 
            data_out => cm_data
        );
    
    AM: AssociativeMemory
        generic map (D => D, K => K, WORD_WIDTH => CHUNK_WIDTH)
        port map (
            clk      => clk, 
            we       => am_we_mux, 
            addr     => am_addr_mux, 
            data_in  => am_data_in_mux, 
            data_out => am_data
        );

    gen_training_ram: if SUPPORT_TRAINING generate
        CC: ClassCounterRAM
            generic map (
                -- Only one physical class-counter block is stored.
                -- The host must train/finalize one label at a time.
                DEPTH => COUNTER_BLOCK_SIZE,
                WIDTH => 11
            )
            port map (
                clk      => clk,
                we       => cc_we,
                addr     => cc_addr,
                data_in  => cc_din,
                data_out => cc_dout
            );
    end generate;

    gen_no_training_ram: if not SUPPORT_TRAINING generate
        cc_dout <= (others => '0');
    end generate;

    im_addr_mux <= im_addr when load_mode = '1' else
                   std_logic_vector(
                       to_unsigned(feature_index * CHUNKS_PER_VEC + chunk_counter, 16)
                   );

    cm_addr_mux <= cm_addr when load_mode = '1' else
                   std_logic_vector(
                       to_unsigned(level_index_next * CHUNKS_PER_VEC + chunk_counter, 16)
                   );

    am_addr_mux <= am_addr;

    MAJ: entity work.MajorityRAM
        generic map (DEPTH => CHUNKS_PER_VEC, WIDTH => CHUNK_WIDTH)
        port map (
            clk   => clk,
            we    => maj_we,
            waddr => maj_wr_addr,
            raddr => maj_rd_addr,
            din   => maj_din,
            dout  => maj_dout
        );

    process(clk, reset)
    begin
        if reset='1' then
            feature_load_index <= 0;
            features_ready     <= '0';
            feature_values     <= (others => (others => '0'));
        elsif rising_edge(clk) then
            if feature_valid='1' and features_ready='0' then
                feature_values(feature_load_index) <= feature_value;

                if feature_load_index = N-1 then
                    features_ready     <= '1';
                    feature_load_index <= 0;
                else
                    feature_load_index <= feature_load_index + 1;
                end if;
            end if;

            -- wenn start kommt, alte Features "verbraucht"
            if start='1' and load_mode='0' then
                features_ready     <= '0';
                feature_load_index <= 0;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Haupt-FSM: Encoding (mit BRAM-Latenz) + Training + Finalisierung + Compare
    --------------------------------------------------------------------
    process(clk, reset)
        variable count_array : counter_array_type := (others => (others => '0'));
        variable xor_v       : std_logic_vector(CHUNK_WIDTH-1 downto 0);
        variable pos_v, lvl_v: std_logic_vector(CHUNK_WIDTH-1 downto 0);
        variable best        : dist_word_t;
        variable idx         : integer := 0;
        variable lab_int     : integer;
        -- Hilfsvariable für Distanz-Update (inkl. letztem Chunk)
        variable dist_next   : dist_word_t;
        -- Adresse im ClassCounterRAM
        variable addr_int    : integer;
        -- Hilfsvariable für Counter-Wert
        variable cnt         : bit_counter_t;
        variable word_next   : std_logic_vector(CHUNK_WIDTH-1 downto 0);
    begin
        if reset='1' then
            state          <= S_IDLE;
            feature_index  <= 0;
            chunk_counter  <= 0;
            count_array    := (others => (others => '0'));
            done           <= '0';
            maj_we         <= '0';
            maj_wr_addr    <= 0;
            maj_rd_addr    <= 0;
            maj_din        <= (others => '0');

            comp_state     <= 0;
            class_idx      <= 0;
            comp_chunk     <= 0;
            dist_acc       <= (others => '0');
            distances      <= (others => (others => '0'));
            comp_xor_reg   <= (others => '0');
            comp_pop_reg   <= (others => '0');
            best_dist      <= (others => '0');
            best_class     <= 0;
            recognized_class <= (others => '0');

            train_class    <= 0;
            train_chunk    <= 0;
            final_class    <= 0;
            final_chunk    <= 0;
            level_index_next <= 0;
            am_we_core     <= '0';

            -- ClassCounterRAM Steuerung
            cc_we         <= '0';
            cc_addr       <= (others => '0');
            cc_din        <= (others => '0');
            train_bit     <= 0;
            train_phase   <= 0;
            final_bit     <= 0;
            final_phase   <= 0;
            word_out_reg  <= (others => '0');
            clear_index   <= 0;

        elsif rising_edge(clk) then
            -- Defaults
            done       <= '0';
            am_we_core <= '0';
            cc_we      <= '0';
            maj_we     <= '0';

            case state is

                ----------------------------------------------------------------
                -- IDLE
                ----------------------------------------------------------------
                when S_IDLE =>
                    -- Trainings-Finalisierung?
                    if (train_mode = '1') and (finalize_training = '1') and (start='1') then
                        -- With the one-class counter RAM, label_in selects the AM row
                        -- that receives the finalized majority vector.
                        lab_int := to_integer(unsigned(label_in));
                        if lab_int < 0 then
                            lab_int := 0;
                        elsif lab_int > K-1 then
                            lab_int := K-1;
                        end if;
                        final_class   <= lab_int;
                        final_chunk   <= 0;
                        final_bit     <= 0;
                        final_phase   <= 0;
                        word_out_reg  <= (others => '0');
                        state         <= S_FINAL_INIT;

                    -- Training eines Samples: Features -> HV -> Counters
                    elsif (train_mode = '1') and (start='1') and (load_mode='0') and (features_ready='1') then
                        feature_index <= 0;
                        chunk_counter <= 0;
                        level_index_next <= level_from_feature(feature_values(0));
                        count_array   := (others => (others => '0'));
                        train_bit     <= 0;
                        train_phase   <= 0;
                        state         <= S_ENC_WAIT;

                    -- Testing: Features -> HV -> Compare mit AM
                    elsif (train_mode = '0') and (start='1') and (load_mode='0') and (features_ready='1') then
                        feature_index <= 0;
                        chunk_counter <= 0;
                        level_index_next <= level_from_feature(feature_values(0));
                        count_array   := (others => (others => '0'));
                        class_idx     <= 0;
                        comp_chunk    <= 0;
                        comp_state    <= 0;
                        state         <= S_ENC_WAIT;
                    end if;

                ----------------------------------------------------------------
                -- ENCODING: Adresse anlegen
                ----------------------------------------------------------------
                when S_ENC_ADDR =>
                    state <= S_ENC_WAIT;

                ----------------------------------------------------------------
                -- ENCODING: 1 Takt warten für BRAM-Latenz
                ----------------------------------------------------------------
                when S_ENC_WAIT =>
                    state <= S_ENC_ACC;

                ----------------------------------------------------------------
                -- ENCODING: XOR + zählen
                ----------------------------------------------------------------
                when S_ENC_ACC =>
                    pos_v := im_data;
                    lvl_v := cm_data;
                    xor_v := pos_v xor lvl_v;

                    for i in 0 to CHUNK_WIDTH-1 loop
                        if xor_v(i)='1' then
                            count_array(i) := count_array(i) + 1;
                        end if;
                    end loop;

                    if feature_index < N-1 then
                        feature_index <= feature_index + 1;
                        level_index_next <= level_from_feature(feature_values(feature_index + 1));
                        state         <= S_ENC_WAIT;
                    else
                        feature_index <= 0;
                        state         <= S_WRITE_MAJ;
                    end if;

                ----------------------------------------------------------------
                -- ENCODING: Majority pro Chunk aus count_array -> majority_ram
                --            (nur über active_chunks)
                ----------------------------------------------------------------
                when S_WRITE_MAJ =>
                    word_next := (others => '0');

                    if (chunk_counter < ACTIVE_CHUNKS) then
                        for i in 0 to CHUNK_WIDTH-1 loop
                            if to_integer(count_array(i)) >= (N / 2) then
                                word_next(i) := '1';
                            else
                                word_next(i) := '0';
                            end if;
                        end loop;

                        maj_we      <= '1';
                        maj_wr_addr <= chunk_counter;
                        maj_din     <= word_next;
                    end if;

                    count_array := (others => (others => '0'));

                    if (chunk_counter < ACTIVE_CHUNKS-1) then
                        chunk_counter <= chunk_counter + 1;
                        level_index_next <= level_from_feature(feature_values(0));
                        state         <= S_ENC_WAIT;
                    else
                        chunk_counter <= 0;

                        if train_mode = '1' then
                            -- Training: Sample-HV in Klassen-Counter akkumulieren
                            lab_int := to_integer(unsigned(label_in));
                            if lab_int < 0 then
                                lab_int := 0;
                            elsif lab_int > K-1 then
                                lab_int := K-1;
                            end if;
                            train_class <= lab_int;
                            train_chunk <= 0;
                            train_bit   <= 0;
                            train_phase <= 0;
                            maj_rd_addr <= 0;
                            state       <= S_TRAIN_ACC;
                        else
                            -- Testing: direkt in Compare-FSM
                            class_idx  <= 0;
                            comp_chunk <= 0;
                            dist_acc   <= (others => '0');
                            comp_state <= 0;
                            maj_rd_addr <= 0;
                            state      <= S_COMPARE;
                        end if;
                    end if;

                when S_TRAIN_ACC =>
                    case train_phase is

                        when 0 =>
                            maj_rd_addr <= train_chunk;
                            addr_int := train_chunk * CHUNK_WIDTH + train_bit;
                            cc_addr     <= std_logic_vector(to_unsigned(addr_int, cc_addr'length));
                            cc_we       <= '0'; 
                            train_phase <= 1;    

                        when 1 =>
                            cc_we       <= '0';
                            train_phase <= 2;  

                        when 2 =>
                            cnt := signed(cc_dout);

                            if maj_dout(train_bit) = '1' then
                                cnt := cnt + 1;
                            else
                                cnt := cnt - 1;
                            end if;

                            cc_din <= std_logic_vector(cnt);
                            cc_we  <= '1';  -- schreiben

                            if train_bit < CHUNK_WIDTH-1 then
                                train_bit   <= train_bit + 1;
                                train_phase <= 0; 
                            else
                                train_bit   <= 0;
                                train_phase <= 0;

                                if (train_chunk < ACTIVE_CHUNKS-1) then
                                    train_chunk <= train_chunk + 1;
                                    maj_rd_addr <= train_chunk + 1;
                                else
                                    done  <= '1';  
                                    state <= S_IDLE;
                                end if;
                            end if;

                        when others =>
                            train_phase <= 0;
                    end case;

                when S_FINAL_INIT =>
                    final_chunk   <= 0;
                    final_bit     <= 0;
                    final_phase   <= 0;
                    word_out_reg  <= (others => '0');
                    state         <= S_FINAL_WRITE;

                when S_FINAL_WRITE =>
                    case final_phase is

                        when 0 =>
                            addr_int := final_chunk * CHUNK_WIDTH + final_bit;
                            cc_addr     <= std_logic_vector(to_unsigned(addr_int, cc_addr'length));
                            cc_we       <= '0';  
                            final_phase <= 1;   

                        when 1 =>
                            cc_we       <= '0';
                            final_phase <= 2;

                        when 2 =>
                            word_next := word_out_reg;
                            if signed(cc_dout) > 0 then
                                word_next(final_bit) := '1';
                            else
                                word_next(final_bit) := '0';
                            end if;
                            word_out_reg <= word_next;

                            if final_bit < CHUNK_WIDTH-1 then
                                final_bit   <= final_bit + 1;
                                final_phase <= 0;  
                            else
                                final_bit   <= 0;
                                final_phase <= 0;

                                am_we_core      <= '1';
                                am_addr_internal <= std_logic_vector(
                                    to_unsigned(final_class * ACTIVE_CHUNKS + final_chunk, 16)
                                );
                                am_data_in_core <= word_next;

                                if final_chunk < ACTIVE_CHUNKS-1 then
                                    final_chunk  <= final_chunk + 1;
                                    word_out_reg <= (others => '0');
                                else
                                    final_chunk  <= 0;
                                    word_out_reg <= (others => '0');
                                    clear_index  <= 0;
                                    state        <= S_CLEAR_COUNTERS;
                                end if;
                            end if;

                        when others =>
                            final_phase <= 0;
                    end case;

                when S_CLEAR_COUNTERS =>
                    -- Clear the single physical counter block after the label
                    -- has been finalized into AM(final_class).
                    cc_addr <= std_logic_vector(to_unsigned(clear_index, cc_addr'length));
                    cc_din  <= (others => '0');
                    cc_we   <= '1';

                    if clear_index < COUNTER_BLOCK_SIZE-1 then
                        clear_index <= clear_index + 1;
                    else
                        clear_index <= 0;
                        done        <= '1';
                        state       <= S_IDLE;
                    end if;

                when S_COMPARE =>
                    case comp_state is

                        when 0 =>
                            am_addr_internal <= std_logic_vector(
                                to_unsigned(class_idx * ACTIVE_CHUNKS, 16)
                            );
                            maj_rd_addr <= 0;
                            comp_state <= 1;

                        when 1 =>
                            comp_state <= 2;

                        when 2 =>
                            comp_xor_reg <= maj_dout xor am_data;
                            comp_state   <= 3;

                        when 3 =>
                            comp_pop_reg <= popcount_word(comp_xor_reg);
                            comp_state   <= 4;

                        when 4 =>
                            dist_next := dist_acc + resize(comp_pop_reg, dist_next'length);

                            if comp_chunk < ACTIVE_CHUNKS-1 then
                                dist_acc      <= dist_next;
                                comp_chunk    <= comp_chunk + 1;
                                maj_rd_addr   <= comp_chunk + 1;
                                am_addr_internal <= std_logic_vector(unsigned(am_addr_internal) + 1);
                                comp_state    <= 1;
                            else
                                distances(class_idx) <= dist_next;
                                dist_acc             <= (others => '0');
                                comp_chunk           <= 0;
                                comp_state           <= 5;
                            end if;

                        when 5 =>
                            if class_idx < A-1 then
                                class_idx <= class_idx + 1;
                                am_addr_internal <= std_logic_vector(unsigned(am_addr_internal) + 1);
                                maj_rd_addr <= 0;
                                comp_state <= 1;
                            else
                                best_dist  <= distances(0);
                                best_class <= 0;
                                class_idx  <= 1;
                                comp_state <= 6;
                            end if;

                        when 6 =>
                            if distances(class_idx) < best_dist then
                                best_dist  <= distances(class_idx);
                                best_class <= class_idx;
                            end if;

                            if class_idx < A-1 then
                                class_idx <= class_idx + 1;
                            else
                                comp_state <= 7;
                            end if;

                        when 7 =>
                            recognized_class <= std_logic_vector(to_unsigned(best_class, 3));
                            done             <= '1';
                            state            <= S_IDLE;
                            comp_state       <= 0;

                        when others =>
                            comp_state <= 0;
                    end case;

                when others =>
                    state <= S_IDLE;

            end case;
        end if;
    end process;

end Behavioral;
