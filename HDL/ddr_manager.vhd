-- DDR4 native application-interface wrapper for the TopM scheduler.
-- Application data is 64 bits wide; the configured physical DQ bus is 8 bits.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity ddr_manager is
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

        -- Legacy start inputs are unused; DDR_State directly selects the operation.
        wr_Start     : in std_logic;
        re_Start     : in std_logic;
        clk_sync_rst : inout std_logic;
        -- Readiness levels: TopM consumes each flag in the corresponding scheduler state.
        en_wr     : out std_logic;
        en_rd     : out std_logic;
        valid_rd  : out std_logic;
        DDR_State : in std_logic_vector(2 downto 0);
        add_wr    : in std_logic_vector(28 downto 0);
        add_rd    : in std_logic_vector(28 downto 0);
        data_wr   : in std_logic_vector(63 downto 0);
        data_rd   : out std_logic_vector(63 downto 0)
    );
end ddr_manager;

architecture Behavioral of ddr_manager is

    -- Keep these state encodings consistent with TopM.
    constant s_write : std_logic_vector(2 downto 0) := "001";
    constant s_read  : std_logic_vector(2 downto 0) := "010";

    signal ddr_addr            : std_logic_vector(28 downto 0);
    signal ddr_app_cmd         : std_logic_vector(2 downto 0);
    signal ddr_app_en          : std_logic;
    signal ddr_app_rd_data_end : std_logic;
    signal ddr_app_wdf_end     : std_logic;
    signal ddr_app_wdf_rdy     : std_logic;
    signal en_ddr              : std_logic;
    signal clk                 : std_logic;
    -- Calibration completion is observed but has no explicit command gate.
    signal s_calib_complete : std_logic;
    signal en_rd_int        : std_logic;
    signal en_wr_int        : std_logic;

    -- Component declaration retained; reconcile auxiliary clock ports with the IP.
    COMPONENT ddr4_0
        PORT (
            c0_init_calib_complete    : OUT STD_LOGIC;
            dbg_clk                   : OUT STD_LOGIC;
            c0_sys_clk_p              : IN STD_LOGIC;
            c0_sys_clk_n              : IN STD_LOGIC;
            dbg_bus                   : OUT STD_LOGIC_VECTOR(511 DOWNTO 0);
            c0_ddr4_adr               : OUT STD_LOGIC_VECTOR(16 DOWNTO 0);
            c0_ddr4_ba                : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
            c0_ddr4_cke               : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
            c0_ddr4_cs_n              : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
            c0_ddr4_dm_dbi_n          : INOUT STD_LOGIC_VECTOR(0 DOWNTO 0);
            c0_ddr4_dq                : INOUT STD_LOGIC_VECTOR(7 DOWNTO 0);
            c0_ddr4_dqs_c             : INOUT STD_LOGIC_VECTOR(0 DOWNTO 0);
            c0_ddr4_dqs_t             : INOUT STD_LOGIC_VECTOR(0 DOWNTO 0);
            c0_ddr4_odt               : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
            c0_ddr4_bg                : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
            c0_ddr4_reset_n           : OUT STD_LOGIC;
            c0_ddr4_act_n             : OUT STD_LOGIC;
            c0_ddr4_ck_c              : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
            c0_ddr4_ck_t              : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
            c0_ddr4_ui_clk            : OUT STD_LOGIC;
            c0_ddr4_ui_clk_sync_rst   : OUT STD_LOGIC;
            c0_ddr4_app_en            : IN STD_LOGIC;
            c0_ddr4_app_hi_pri        : IN STD_LOGIC;
            c0_ddr4_app_wdf_end       : IN STD_LOGIC;
            c0_ddr4_app_wdf_wren      : IN STD_LOGIC;
            c0_ddr4_app_rd_data_end   : OUT STD_LOGIC;
            c0_ddr4_app_rd_data_valid : OUT STD_LOGIC;
            c0_ddr4_app_rdy           : OUT STD_LOGIC;
            c0_ddr4_app_wdf_rdy       : OUT STD_LOGIC;
            c0_ddr4_app_addr          : IN STD_LOGIC_VECTOR(28 DOWNTO 0);
            c0_ddr4_app_cmd           : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
            c0_ddr4_app_wdf_data      : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
            c0_ddr4_app_wdf_mask      : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
            c0_ddr4_app_rd_data       : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
            -- These ports are absent from the currently packaged ddr4_0 configuration.
            addn_ui_clkout1 : OUT STD_LOGIC;
            addn_ui_clkout2 : OUT STD_LOGIC;
            addn_ui_clkout3 : OUT STD_LOGIC;
            addn_ui_clkout4 : OUT STD_LOGIC;
            sys_rst         : IN STD_LOGIC
        );
    END COMPONENT;

begin

    clk_ddr <= clk;

    -- DDR4 native interface; the UI reset is forwarded to the scheduler.
    Inst_ddr4 : ddr4_0
        PORT MAP (
            c0_init_calib_complete => s_calib_complete,
            sys_rst                => i_Reset,
            dbg_clk                => open,
            dbg_bus                => open,

            c0_sys_clk_p     => c0_sys_clk_p,
            c0_sys_clk_n     => c0_sys_clk_n,
            c0_ddr4_adr      => ddr4_adr,
            c0_ddr4_ba       => ddr4_ba,
            c0_ddr4_cke      => ddr4_cke,
            c0_ddr4_cs_n     => ddr4_cs_n,
            c0_ddr4_dm_dbi_n => ddr4_dm_dbi_n,
            c0_ddr4_dq       => ddr4_dq,
            c0_ddr4_dqs_c    => ddr4_dqs_c,
            c0_ddr4_dqs_t    => ddr4_dqs_t,
            c0_ddr4_odt      => ddr4_odt,
            c0_ddr4_bg       => ddr4_bg,
            c0_ddr4_reset_n  => ddr4_reset_n,
            c0_ddr4_act_n    => ddr4_act_n,
            c0_ddr4_ck_c     => ddr4_ck_c,
            c0_ddr4_ck_t     => ddr4_ck_t,

            c0_ddr4_app_hi_pri      => '0',
            c0_ddr4_ui_clk          => clk,
            c0_ddr4_ui_clk_sync_rst => clk_sync_rst,

            c0_ddr4_app_rdy  => en_rd_int,
            c0_ddr4_app_en   => ddr_app_en,
            c0_ddr4_app_cmd  => ddr_app_cmd,
            c0_ddr4_app_addr => ddr_addr,

            c0_ddr4_app_wdf_rdy  => ddr_app_wdf_rdy,
            c0_ddr4_app_wdf_end  => ddr_app_wdf_end,
            c0_ddr4_app_wdf_wren => en_ddr,
            c0_ddr4_app_wdf_data => data_wr,
            c0_ddr4_app_wdf_mask => (others => '0'),

            addn_ui_clkout1 => refclk,
            addn_ui_clkout2 => gtx_clk,
            addn_ui_clkout3 => s_axi_aclk,
            addn_ui_clkout4 => clk_20M,

            c0_ddr4_app_rd_data_end   => ddr_app_rd_data_end,
            c0_ddr4_app_rd_data_valid => valid_rd,
            c0_ddr4_app_rd_data       => data_rd
        );
    -- Accept a write only when command and write-data channels are both ready.
    en_wr_int <= ddr_app_wdf_rdy and en_rd_int;
    en_rd     <= en_rd_int;
    en_wr     <= en_wr_int;

    -- Write command: 000. Read command: 001. Other states issue no command.
    en_ddr          <= en_wr_int  when DDR_State = s_write else '0';
    ddr_app_wdf_end <= en_wr_int  when DDR_State = s_write else '0';
    ddr_app_cmd     <= "000"  when DDR_State = s_write else "001";
    ddr_addr        <= add_wr when DDR_State = s_write else add_rd;
    ddr_app_en      <= en_wr_int  when DDR_State = s_write else en_rd_int when DDR_State = s_read   else  '0';

end Behavioral;
