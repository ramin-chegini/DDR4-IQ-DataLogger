-- I/Q and IF data logger: acquisition FIFO -> DDR4 -> output FIFO.
-- Data_clk accepts samples; clk_ddr schedules memory; rd_clk serves the consumer.
-- PCIe transport belongs to the parent system.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_misc.all;

library UNISIM;
use UNISIM.VComponents.all;

entity TopM is
    Port (
        -- Glb_rst resets the DDR4 IP; Reset resets the data FIFOs.
        Glb_rst  : in  std_logic;
        clk_in_p : in  std_logic;
        clk_in_n : in  std_logic;

        -- Physical DDR4 interface: widths follow the current IP configuration.
        c0_ddr4_adr      : OUT STD_LOGIC_VECTOR(16 DOWNTO 0);
        c0_ddr4_ba       : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
        c0_ddr4_cke      : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
        c0_ddr4_cs_n     : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
        c0_ddr4_dm_dbi_n : INOUT STD_LOGIC_VECTOR(0 DOWNTO 0);
        c0_ddr4_dq       : INOUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        c0_ddr4_dqs_c    : INOUT STD_LOGIC_VECTOR(0 DOWNTO 0);
        c0_ddr4_dqs_t    : INOUT STD_LOGIC_VECTOR(0 DOWNTO 0);
        c0_ddr4_odt      : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
        c0_ddr4_bg       : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
        c0_ddr4_reset_n  : OUT STD_LOGIC;
        c0_ddr4_act_n    : OUT STD_LOGIC;
        c0_ddr4_ck_c     : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
        c0_ddr4_ck_t     : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);

        -- Capture limit in 512-word blocks; the scheduler permits length + 1 blocks.
        IQ_Buffer_length : in STD_LOGIC_VECTOR(31 DOWNTO 0);

        -- Auxiliary clocks requested from ddr_manager; check the packaged IP configuration.
        refclk     : out std_logic;
        gtx_clk    : out std_logic;
        s_axi_aclk : out std_logic;
        clk_20M    : out std_logic;

        -- Both acquisition FIFOs accept LOG_in on LOG_in_val in the Data_clk domain.
        Data_clk                 : in STD_LOGIC;
        Reset                    : in STD_LOGIC;
        LOG_in                   : in STD_LOGIC_VECTOR(31 DOWNTO 0);
        Log_in_val               : in STD_LOGIC;
        IQ_EN                    : in STD_LOGIC;
        LOG_EN                   : in STD_LOGIC;
        Monitoring_Log_Start     : in STD_LOGIC;
        Monitoring_Data_release  : in STD_LOGIC;
        MaxHold_Monitoring_EN    : in STD_LOGIC;
        IF_Monitoring_Busy       : inout STD_LOGIC;
        IF_Monitoring_Data_Ready : inout STD_LOGIC;

        -- External consumer interface; IF_Data_rdy reports a FIFO occupancy threshold.
        rd_clk        : in std_logic;
        Log_out_rd_en : in std_logic;
        LOG_out       : out STD_LOGIC_VECTOR(15 DOWNTO 0);

        IF_Data_rdy : out std_logic

    );
end TopM;

architecture Behavioral of TopM is
    -- Memory wrapper and vendor FIFO component interfaces.
    component ddr_manager
        Port (
            i_Reset      : in STD_LOGIC;
            c0_sys_clk_p : IN STD_LOGIC;
            c0_sys_clk_n : IN STD_LOGIC;
            clk_ddr      : out std_logic;
            refclk       : out std_logic;
            gtx_clk      : out std_logic;
            s_axi_aclk   : out std_logic;
            clk_20M      : out std_logic;

            ddr4_adr      : out std_logic_vector(16 downto 0);
            ddr4_ba       : out std_logic_vector(1 downto 0);
            ddr4_cke      : out std_logic_vector(0 downto 0);
            ddr4_cs_n     : out std_logic_vector(0 downto 0);
            ddr4_dm_dbi_n : inout std_logic_vector(0 downto 0);
            ddr4_dq       : inout std_logic_vector(7 downto 0);
            ddr4_dqs_c    : inout std_logic_vector(0 downto 0);
            ddr4_dqs_t    : inout std_logic_vector(0 downto 0);
            ddr4_odt      : out std_logic_vector(0 downto 0);
            ddr4_bg       : out std_logic_vector(0 downto 0);
            ddr4_reset_n  : out std_logic;
            ddr4_act_n    : out std_logic;
            ddr4_ck_c     : out std_logic_vector(0 downto 0);
            ddr4_ck_t     : out std_logic_vector(0 downto 0);

            wr_Start     : in std_logic;
            re_Start     : in std_logic;
            clk_sync_rst : inout std_logic;
            en_wr        : out std_logic;
            en_rd        : out std_logic;
            valid_rd     : out std_logic;
            DDR_State    : in std_logic_vector(2 downto 0);
            add_wr       : in std_logic_vector(28 downto 0);
            add_rd       : in std_logic_vector(28 downto 0);
            data_wr      : in std_logic_vector(63 downto 0);
            data_rd      : out std_logic_vector(63 downto 0)
        );
    end component;

    COMPONENT IFREC_fifo
        PORT (
            rst         : IN STD_LOGIC;
            wr_clk      : IN STD_LOGIC;
            rd_clk      : IN STD_LOGIC;
            din         : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
            wr_en       : IN STD_LOGIC;
            rd_en       : IN STD_LOGIC;
            dout        : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
            full        : OUT STD_LOGIC;
            empty       : OUT STD_LOGIC;
            prog_full   : OUT STD_LOGIC;
            wr_rst_busy : OUT STD_LOGIC;
            rd_rst_busy : OUT STD_LOGIC
        );
    END Component;
    COMPONENT IQ_LOG_FIFO
        PORT (
            rst         : IN STD_LOGIC;
            wr_clk      : IN STD_LOGIC;
            rd_clk      : IN STD_LOGIC;
            din         : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
            wr_en       : IN STD_LOGIC;
            rd_en       : IN STD_LOGIC;
            dout        : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
            full        : OUT STD_LOGIC;
            empty       : OUT STD_LOGIC;
            prog_full   : OUT STD_LOGIC;
            wr_rst_busy : OUT STD_LOGIC;
            rd_rst_busy : OUT STD_LOGIC
        );
    END Component;
    COMPONENT IF_output_FIFO
        PORT (
            srst        : IN STD_LOGIC;
            wr_clk      : IN STD_LOGIC;
            rd_clk      : IN STD_LOGIC;
            din         : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
            wr_en       : IN STD_LOGIC;
            rd_en       : IN STD_LOGIC;
            dout        : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            full        : OUT STD_LOGIC;
            empty       : OUT STD_LOGIC;
            prog_full   : OUT STD_LOGIC;
            prog_empty  : OUT STD_LOGIC;
            wr_rst_busy : OUT STD_LOGIC;
            rd_rst_busy : OUT STD_LOGIC
        );
    END COMPONENT;
    -- Legacy start signals are retained; ddr_manager does not use them.
    signal wr_Start      : std_logic;
    signal re_Start      : std_logic;
    signal FIFO_wr_Start : std_logic;
    signal FIFO_re_Start : std_logic;
    signal clk_sync_rst  : std_logic;
    -- Scheduler encoding must match the constants in ddr_manager.
    constant s_idle         : std_logic_vector(2 downto 0) := "000";
    constant s_write        : std_logic_vector(2 downto 0) := "001";
    constant s_read         : std_logic_vector(2 downto 0) := "010";
    constant s_Wait4read    : std_logic_vector(2 downto 0) := "011";
    constant s_resetCycle   : std_logic_vector(2 downto 0) := "100";
    signal DDR_State        : std_logic_vector(2 downto 0) := s_idle;
    signal FIFO_in_State    : std_logic_vector(2 downto 0) := s_idle;
    signal add_wr           : std_logic_vector(28 downto 0);
    signal add_rd           : std_logic_vector(28 downto 0);
    signal data_rd          : std_logic_vector(63 downto 0);
    signal data_wr          : std_logic_vector(63 downto 0);
    signal LOG_buffer_count : std_logic_vector(31 downto 0);
    signal RD_buffer_count  : std_logic_vector(31 downto 0);

    signal IFREC_fifo_dout  : std_logic_vector(63 downto 0);
    signal IQREC_fifo_dout  : std_logic_vector(63 downto 0);
    signal IFREC_fifo_rd_en : std_logic;
    signal IQREC_fifo_rd_en : std_logic;
    signal IFREC_fifo_wr_en : std_logic;
    signal en_wr            : std_logic;
    signal IQ_prog_full     : std_logic;
    signal If_prog_full     : std_logic;
    signal Write_trig       : std_logic;
    signal rst_auto         : std_logic;
    signal reset_counter    : STD_LOGIC_VECTOR(31 DOWNTO 0) := (others => '0');
    signal en_rd            : std_logic;
    signal clk_ddr          : std_logic;
    signal cou_led          : std_logic_vector(27 downto 0) := (others => '0');
    signal LOGStart         : std_logic := '0';
    signal valid_rd         : std_logic;
    signal IFREC_fifo_din   : std_logic_vector(15 downto 0) := (others => '0');
    signal cou              : std_logic_vector(15 downto 0) := (others => '0');
    signal data_old         : std_logic_vector(15 downto 0) := (others => '0');
    signal diff_data        : std_logic_vector(15 downto 0) := (others => '0');

    signal IF_output_FIFO_rd_en : std_logic;
    signal Log_out_rd_en_int    : std_logic;
    signal IF_output_FIFO_prog_full, IF_output_FIFO_prog_empty : std_logic;
    signal IF_Monitoring_Release : std_logic;
    signal IF_output_FIFO_empty  : std_logic;
    signal IF_output_FIFO_dout   : std_logic_vector(15 downto 0);
    signal wr_cnt                : std_logic_vector(31 downto 0) := (others => '0');
    signal re_cnt                : std_logic_vector(31 downto 0) := (others => '0');
    -- One scheduler block contains 512 accepted 64-bit transfers (4096 payload bytes).
    constant burst_size : std_logic_vector(31 downto 0) := x"0000_0200";
    -- Legacy size declaration retained from the original implementation.
    signal data_size : std_logic_vector(31 downto 0) := x"0186_A000";
    -- Debug word balance updated at block completion, not on read-data return.
    signal Writedata_size : std_logic_vector(31 downto 0) := x"0000_0000";

begin
    -- DDR4 wrapper supplies the UI clock, synchronous reset and acceptance flags.
    Inst_ddr : ddr_manager
        PORT MAP (
            i_Reset      => Glb_rst,
            c0_sys_clk_p => clk_in_p,
            c0_sys_clk_n => clk_in_n,
            clk_ddr      => clk_ddr,
            refclk       => refclk,
            gtx_clk      => gtx_clk,
            s_axi_aclk   => s_axi_aclk,
            clk_20M      => clk_20M,

            ddr4_adr      => c0_ddr4_adr,
            ddr4_ba       => c0_ddr4_ba,
            ddr4_cke      => c0_ddr4_cke,
            ddr4_cs_n     => c0_ddr4_cs_n,
            ddr4_dm_dbi_n => c0_ddr4_dm_dbi_n,
            ddr4_dq       => c0_ddr4_dq,
            ddr4_dqs_c    => c0_ddr4_dqs_c,
            ddr4_dqs_t    => c0_ddr4_dqs_t,
            ddr4_odt      => c0_ddr4_odt,
            ddr4_bg       => c0_ddr4_bg,
            ddr4_reset_n  => c0_ddr4_reset_n,
            ddr4_act_n    => c0_ddr4_act_n,
            ddr4_ck_c     => c0_ddr4_ck_c,
            ddr4_ck_t     => c0_ddr4_ck_t,

            wr_Start     => wr_Start,
            re_Start     => re_Start,
            clk_sync_rst => clk_sync_rst,
            DDR_State    => DDR_State,
            add_wr       => add_wr,
            add_rd       => add_rd,
            data_wr      => data_wr,
            data_rd      => data_rd,
            en_wr        => en_wr,
            en_rd        => en_rd,
            valid_rd     => valid_rd
        );

    -- IF path: pack four lower-halfword samples into each 64-bit FIFO output.
    IFREC_fifo_INST : IFREC_fifo
        PORT MAP (
            rst => reset or rst_auto,

            wr_clk => Data_CLK,
            din    => LOG_in(15 downto 0),
            wr_en  => LOG_in_val,

            rd_clk => clk_ddr,
            rd_en  => IFREC_fifo_rd_en,
            dout   => IFREC_fifo_dout,

            full        => open,
            empty       => open,
            prog_full   => IF_prog_full,
            wr_rst_busy => open,
            rd_rst_busy => open
        );

    -- I/Q path: pack two complete 32-bit input words into each 64-bit FIFO output.
    IQ_LOG_FIFO_INST : IQ_LOG_FIFO
        PORT MAP (
            rst => reset,

            wr_clk => Data_CLK,
            din    => LOG_in,
            wr_en  => LOG_in_val,

            rd_clk => clk_ddr,
            rd_en  => IQREC_fifo_rd_en,
            dout   => IQREC_fifo_dout,

            full        => open,
            empty       => open,
            prog_full   => IQ_prog_full,
            wr_rst_busy => open,
            rd_rst_busy => open
        );

    -- Monitoring release is passed directly to the DDR-domain control logic.
    IF_Monitoring_Release <= Monitoring_Data_release;

    -- During writes both input FIFOs advance; disabled paths are drained in idle.
    IFREC_fifo_rd_en <= en_wr WHEN DDR_State = s_write ELSE '1' when (LOG_EN = '0' and DDR_State = s_idle and MaxHold_Monitoring_EN = '0') else '0';
    IQREC_fifo_rd_en <= en_wr WHEN DDR_State = s_write ELSE '1' when (IQ_EN = '0'  and DDR_State = s_idle) else '0';

    -- IF logging/monitoring takes priority over I/Q when selecting write data.
    data_wr <= IFREC_fifo_dout when (LOG_en = '1' or Monitoring_Log_Start = '1') else
        IQREC_fifo_dout when (IQ_EN = '1')  else
        (others => '0');
    -- Programmable-full thresholds provide a block of data before writes start.
    Write_trig <= IF_prog_full when (LOG_en = '1' or Monitoring_Log_Start = '1') else
        IQ_prog_full when (IQ_EN = '1')  else
        '0';
    -- Scheduler counters, addresses and monitoring flags update on clk_ddr.
    process (clk_ddr, LOG_en, clk_sync_rst)
    begin
        if rising_edge(clk_ddr) then

            if clk_sync_rst = '1'  then
                DDR_State                <= s_idle;
                wr_cnt                   <= (others => '0');
                add_wr                   <= (others => '0');
                re_cnt                   <= (others => '0');
                add_rd                   <= (others => '0');
                Writedata_size           <= (others => '0');
                LOG_buffer_count         <= (others => '0');
                RD_buffer_count          <= (others => '0');
                IF_Monitoring_Busy       <= '0';
                IF_Monitoring_Data_Ready <= '0';
            else
                case DDR_State is

                    -- Prefer pending writes; read stored data when the output FIFO is empty.
                    when s_idle =>
                        wr_cnt <= (others => '0');
                        re_cnt <= (others => '0');
                        if (MaxHold_Monitoring_EN = '0') then
                            if ((Write_trig = '1') and (LOG_buffer_count < (IQ_Buffer_length + 1))) then
                                DDR_State <= s_write;
                            elsif ((RD_buffer_count < LOG_buffer_count) and (IF_output_FIFO_empty = '1'))  then
                                DDR_State <= s_read;
                            end if;
                            IF_Monitoring_Data_Ready <= '0';
                            IF_Monitoring_Busy       <= '0';
                        else
                            if ((Write_trig = '1') and (LOG_buffer_count < (IQ_Buffer_length + 1))) then
                                DDR_State <= s_write;
                            elsif (LOG_buffer_count = (IQ_Buffer_length + 1))  then
                                if ((RD_buffer_count < LOG_buffer_count) and (IF_output_FIFO_empty = '1') and (IF_Monitoring_Busy = '1' or IF_Monitoring_Release = '1'))  then
                                    IF_Monitoring_Busy <= '1';
                                    DDR_State          <= s_read;
                                elsif (RD_buffer_count >= LOG_buffer_count) then
                                    IF_Monitoring_Busy <= '0';
                                end if;
                                if (RD_buffer_count < LOG_buffer_count and MaxHold_Monitoring_EN = '1') then
                                    IF_Monitoring_Data_Ready <= '1';
                                else
                                    IF_Monitoring_Data_Ready <= '0';
                                end if;
                            end if;
                        end if;
                        if (LOG_en = '0' and IQ_EN = '0' and MaxHold_Monitoring_EN = '0') then
                            Writedata_size   <= (others => '0');
                            LOG_buffer_count <= (others => '0');
                            RD_buffer_count  <= (others => '0');
                            add_wr           <= (others => '0');
                            add_rd           <= (others => '0');
                        end if;

                    -- Advance only when the command and write-data channels can accept together.
                    when s_write =>
                        if en_wr = '1' then
                            wr_cnt <= wr_cnt + 1;
                            add_wr <= add_wr + 8;
                            if wr_cnt >= burst_size - 1 then
                                DDR_State        <= s_idle;
                                Writedata_size   <= Writedata_size + burst_size;
                                LOG_buffer_count <= LOG_buffer_count + '1';
                            end if;
                        end if;

                    -- Count accepted read commands; capture returned data separately on valid_rd.
                    when s_read =>

                        if en_rd = '1'  then
                            re_cnt <= re_cnt + 1;
                            add_rd <= add_rd + 8;
                            if  re_cnt >= burst_size - 1  then
                                DDR_State       <= s_idle;
                                Writedata_size  <= Writedata_size - burst_size;
                                RD_buffer_count <= RD_buffer_count + '1';
                            end if;
                        end if;
                    -- Legacy reset sequence: the current state machine has no transition into it.
                    when s_resetCycle =>
                        reset_counter    <= reset_counter + 1;
                        RD_buffer_count  <= (others => '0');
                        LOG_buffer_count <= (others => '0');
                        if reset_counter >= x"0000_0020" then
                            DDR_State          <= s_idle;
                            rst_auto           <= '0';
                            IF_Monitoring_Busy <= '0';
                            reset_counter      <= (others => '0');
                        elsif reset_counter <= x"0000_000A" then
                            rst_auto <= '1';
                        else
                            rst_auto <= '0';
                        end if;
                    when others =>
                        DDR_State <= s_idle;
                end case;

            end if;
        end if;
    end process;

    -- Readback path: unpack each returned 64-bit word into four 16-bit words.
    IF_output_FIFO_inst : IF_output_FIFO
        PORT MAP (
            srst        => reset,
            wr_clk      => clk_ddr,
            rd_clk      => rd_clk,
            din         => data_rd,
            wr_en       => valid_rd,
            rd_en       => Log_out_rd_en_int,
            dout        => IF_output_FIFO_dout,
            full        => open,
            empty       => IF_output_FIFO_empty,
            prog_empty  => IF_output_FIFO_prog_empty,
            prog_full   => IF_output_FIFO_prog_full,
            wr_rst_busy => open,
            rd_rst_busy => open
        );
    -- Threshold-based readiness; Standard_FIFO read latency applies to LOG_out.
    IF_Data_rdy <= IF_output_FIFO_prog_full;
    Log_out     <= IF_output_FIFO_dout;
    -- Drain the output FIFO when all capture and monitoring modes are off.
    Log_out_rd_en_int <= '1' when  (LOG_EN = '0' and IQ_EN = '0' and MaxHold_Monitoring_EN = '0') else Log_out_rd_en;

    -- DDR-clock ILA probes expose scheduler progress, addresses, data and counters.
    test_ddr : entity work.ila_0
        PORT MAP (
            clk       => clk_ddr,
            probe0    => DDR_State,
            probe1    => add_wr,
            probe2    => add_rd,
            probe3    => data_wr,
            probe4    => IFREC_fifo_dout,
            probe5(0) => en_wr,
            probe6(0) => IF_Monitoring_Busy,
            probe7(0) => Write_trig,
            probe7(1) => IF_Monitoring_Data_Ready,
            probe7(2) => IF_output_FIFO_empty,
            probe7(3) => IF_prog_full,
            probe7(4) => Log_out_rd_en,
            probe7(5) => IF_output_FIFO_prog_full,
            probe7(6) => Monitoring_Data_release,
            probe8(0) => MaxHold_Monitoring_EN,
            probe9(0) => valid_rd,
            probe10   => data_rd,
            probe11   => Writedata_size,

            probe12 => wr_cnt,

            probe13 => IQ_Buffer_length,
            probe14 => LOG_buffer_count,
            probe15 => RD_buffer_count

        );

end Behavioral;
