
//--------------------------------------------------------------------------------------------------------
// Module  : ddr_sdram_ctrl
// Type    : synthesizable, IP's top
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: DDR1 SDRAM controller
//           with AXI4 interface
//--------------------------------------------------------------------------------------------------------

module ddr_sdram_ctrl #(
    parameter   READ_BUFFER = 0,

    parameter   BA_BITS     = 2,
    parameter   ROW_BITS    = 13,
    parameter   COL_BITS    = 11,
    parameter   DQ_LEVEL    = 1,    // DDR           DQ_BITS = 4<<DQ_LEVEL  , AXI DATA WIDTH = 8<<DQ_LEVEL, for example:
                                    // DQ_LEVEL = 0: DQ_BITS = 4  (x4)      , AXI DATA WIDTH = 8
                                    // DQ_LEVEL = 1: DQ_BITS = 8  (x8)      , AXI DATA WIDTH = 16    (default)
                                    // DQ_LEVEL = 2: DQ_BITS = 16 (x16)     , AXI DATA WIDTH = 32

    parameter   DQ_BITS     = 4<<DQ_LEVEL,                          /// 8
    parameter   AXI_DW      = 8<<DQ_LEVEL,                          /// 16
    parameter   AXI_AW      = BA_BITS+ROW_BITS+COL_BITS+DQ_LEVEL-1, /// 26 = 2+13+11+1-1
    parameter   DQS_BITS    = ((1<<DQ_LEVEL)+1)/2,                  /// 1
    parameter   DM_BITS     = DQS_BITS,                             /// 1

    parameter   tREFC       = 10'd256,
    parameter   tW2I        = 8'd6,
    parameter   tR2I        = 8'd6
) (
    // driving clock and reset
    input  wire                                                 i_rstn_async        ,
    input  wire                                                 i_drv_clk           ,   // driving clock, typically 300~532MHz
    // generate clock for AXI4
    output reg                                                  rst_n               ,
    output reg                                                  clk                 ,   // freq = F(i_drv_clk)/4
    // user interface (AXI4)
    input  wire                                                 i_awvalid           ,
    output wire                                                 o_awready           ,
    input  wire     [AXI_AW-1:0]                                i_awaddr            ,   // 26, byte address, not word address.
    input  wire     [8-1:0]                                     i_awlen             ,   // 8

    input  wire                                                 i_wvalid            ,
    output wire                                                 o_wready            ,
    input  wire                                                 i_wlast             ,
    input  wire     [AXI_DW-1:0]                                i_wdata             ,   // 16

    output wire                                                 o_bvalid            ,
    input  wire                                                 i_bready            ,

    input  wire                                                 i_arvalid           ,
    output wire                                                 o_arready           ,
    input  wire     [AXI_AW-1:0]                                i_araddr            ,   // 26, byte address, not word address.
    input  wire     [8-1:0]                                     i_arlen             ,   // 8

    output wire                                                 o_rvalid            ,
    input  wire                                                 i_rready            ,
    output wire                                                 o_rlast             ,
    output wire     [AXI_DW-1:0]                                o_rdata             ,   // 16
    // DDR-SDRAM interface
    output wire                                                 o_ddr_ck_p          ,   // freq = F(i_drv_clk)/4
    output wire                                                 o_ddr_ck_n          ,
    output wire                                                 o_ddr_cke           ,   /// clock enable
    output reg                                                  o_ddr_cs_n          ,   /// chip select
    output reg                                                  o_ddr_ras_n         ,   /// row addr strobe
    output reg                                                  o_ddr_cas_n         ,   /// col addr strobe
    output reg                                                  o_ddr_we_n          ,   /// write enable
    output reg      [BA_BITS-1:0]                               o_ddr_ba            ,   // 2    bank selection
    output reg      [ROW_BITS-1:0]                              o_ddr_a             ,   // 13   addressing
    output wire     [DM_BITS-1:0]                               o_ddr_dm            ,   // 1    data mask
    inout           [DQS_BITS-1:0]                              io_ddr_dqs          ,   // 1    data strobe
    inout           [DQ_BITS-1:0]                               io_ddr_dq               // 8    data
);
/// https://en.wikipedia.org/wiki/Synchronous_dynamic_random-access_memory

///     Commands
///     __      ___     ___     __
///     CS      RAS     CAS     WE      BAn     A10     An
///     H       x       x       x       x       x       x           Commend inhibit(no operation)
///     L       H       H       H       x       x       x           No operation
///     L       H       H       L       x       x       x           Burst terminate:stop a burst read or burst write in process
///     L       H       L       H       bank    L       col         Read:read a burst of data from the currently active row
///     L       H       L       H       bank    H       col         Read with auto precharge:as above, and precharge (close row) when done
///     L       H       L       L       bank    L       col         Write:write a burst of data to the currently active row
///     L       H       L       L       bank    H       col         Write with auto precharge:as above, and precharge (close row) when done
///     L       L       H       H       bank    row--------         Active(activate):open a row for read and write commands
///     L       L       H       L       bank    L       x           Precharge:deactivate(close)the current row of selected bank
///     L       L       H       L       x       H       x           Precharge all:deactivate(close) the current row of all banks
///     L       L       L       H       x       x       x           Auto refresh:refresh one row of each bank, using an internal counter.All banks must be precharged.
///     L       L       L       L       0 0     mode-------         Load mode register:A0 through A9 are loaded to configure the DRAM chip.
///                                                                     The most significant settings are CAS latency(2 or 3 cycles) and burst length(1,2,4 or 8 cycles)

/// Construction and operation
/// A typical 512 Mbit SDRAM chip internally contains 4 independent 16 MB memory banks. Each bank is an array of 8192 rows of 16384 bits each.(2048 8-bit columns).
/// A bank is either idle, active, or changing from one to the other.
///
/// The active command activates an idle bank.It presents a two-bit bank address(BA0-BA1) and a 13-bit row address(A0-A12), and causes a read of that row into the bank's array of all 16384 column sense amplifiers.
/// This is also known as "opening" the row. This operation has the side effect of refreshing the dynamic(capacitive) memory storage cells of that row.
///
/// Once the row has been activated or "opened", reaa and write commands are possible to that row.
/// Activation requires a minimum amount of time, called the row-to-column delay, or tRCD before reads or writes to it may occur.
/// This time, rounded up to the next multiple of the clock period, specifies the minimum number of wait cycles between an active command, and a read or write command.
/// During these wait cycles, additional commands may be sent to other banks; because each bank operates completely independently.
///
/// Both read and write commands require a column address. Because each chip accesses 8 bits of date at a time,there are 2048 possible column addresses thus requiring only 11 address lines(A0-A9, A11).
///
/// When a read command is issued, the SDRAM will produce the corresponding output data on the DQ lines in time for the rising edge of the clock a few clock cycles later, depending on the configured CAS latency.
/// Subsequent words of the burst will be produced in time for subsequent rising clock edges.
///
/// A write command is accompanied by the data to be written driven on to the DQ lines during the same rising clock edge.
/// It is the duty of the memory controller to ensure that the SDRAM is not driving read data on to the DQ lines at the same time that is needs to drive write data on to those lines.
/// This can be done by waiting until a read burst has finished, by terminating a read burst, or by using the DQM control line.
///
/// When the memory controller needs to access a different row, it must first return that bank's sense amplifiers to an idle state, ready to sense the next row.
/// This is knowns as a "precharge" operations, or "closing" the row.
/// A precharge may be commanded explicitly, or it may be performed automatically at the conclusion of a read of write operation.
/// Again, there is a minimum time, the row precharge delay, tRP, which must elapse before that row is fully "closed" and so the bank is idle in order to receive another activate command on that bank.

/// Although refreshing a row is an automatic side effect of activating it, there is a minimum time for this to happen, which requires a minimum row access time tRAS delay between an active command opening a row,
/// and the corresponding parecharge command closing it.
/// This limit is usually dwarfed by desired read and write commands to the row, so its value has little effect on typical performance.

/// Command interactions
/// The no operation command is always permitted, while the load mode register command requires that all banks be idle, and a delay afterword for the changes to take effect.
/// The auto refresh command also requires that all banks be idle, and takes a refresh cycle time tRFC to return the chip to the idle state.(This time is usually equal to tRCD+tRP.)
/// The only other command that is permitted on an idle bank is the active command. This takes, as mentioned above, tRCD before the row is fully open and can accept read and write commands.
///
/// When a bank is open, there are four commands permitted:read, write, burst terminate, and precharge. Read an write commands begin bursts, which can be interrupted by following commands.

/// Interrupting a read burst
/// A read, burst terminate, or precharge command may be issued at any time after a read command, and will interrupt the read burst after the configured CAS latency.
/// So if a read command is issued on cycle 0, another read command is issued on cycle 2, and the CAS latency is 3,then the first read command will begin bursting data out during cycles 3 and 4,
/// then the results from the second read command will appear beginning with cycle 5.
///
/// If the command issued on cycle 2 were burst terminate, or a precharge of the active bank, then no output would be generated during cycle 5.
///
/// Although the interrupting read may be to any active bank, a precharge command will only interrupt the read burst if it is to the same bank or all banks; a precharge command to a different bank will not interrupt a read burst.
///
/// Interrupting a read burst by a write command is possible, but more difficult.
/// It can be done if the DQM signal is used to suppress output from the SDRAM so that the memory controller may drive data over the DQ lines to the SDRAM in time for the write operation.
/// Because the effects of DQM on read data are delayed by two cycles, but the effects of DQM on write data are immediate, DQM must be raised(to mask the read data) beginning at least two cycles before write command
/// but must be lowered for the cycle of the write command(assuming the write command is intended to have an effect).
///
/// Doing this in only two clock cycles requires careful coordination between the time the SDRAM takes to turn off its output on a clock edge and the time the data must be supplied as input to the SDRAM for the write on the following clock edge.
/// If the clock frequency if too high to allow sufficient time, three cycles may be required.
///
/// If the read command includes auto-precharge, the precharge begins the same cycle as the interrupting command.

/// Burst ordering
/// A modern microprocessor with a cache will generally access memory in units of cache lines.
/// To transfer a 64-byte cache line requires 8 consecutive accesses to a 64-bit DIMM, which can all be triggered by a single read or write command by configuring the SDRAM chips,using the mode register, to perform eight-word bursts.
/// A cache line fetch is typically triggered by a read from a particular address, and SDRAM allows the "critical word" of the cache line to be transferred first.
/// ("Word" here refers to the width of the SDRAM chip or DIMM, which is 64 bits for a typical DIMM.) SDRAM chips support two possible conventions for the ordering of the remaining words in the cache line.
///
/// Burst always access an aligned block of BL consecutive words beginning on a multiple of BL. So, for example, a four-word burst access to any column address from four to seven will return words four to seven.
/// The ordering, however, depends on the requested address, and the configured burst type option:sequential or interleavec. Typically, a memory controller will require one or the other.
/// When the burst length is one or two, the burst type does not matter. For a burst length of one, the requested word is the only word accessed.
/// For a burst length of two, the requested word is accessed first, and the other word in the aligned block is accessed second. This is the following word if an even address was specified, and the previous word if an odd address was specified.
///
/// For the sequential burst mode, later words are accessed in increasing address order, wrapping back to the start of the block when the end is reached.
/// So, for example, for a burst lenght of four, and a requested column address of five, the words would be accessed in the order 5-6-7-4. If the burst lenght were eight, the access order would be 5-6-7-0-1-2-3-4.
/// This is done by adding a counter to the column address, and ignoring carries past the burst lenght.
/// The interleaved burst mode computes the address using an exclusive or operation between the counter and the address.
/// Usng the same starting address of five, a four-word burst would return words in the order 5-4-7-6.An eight-word burst would be 5-4-7-6-1-0-3-2.
/// Although more confusing to humans, this can be easier to implement in haraware, and is preferred by Intel for its microprocessors.
///
/// If the requested column address is at the start of a block, both burst modes (sqeuential and interleaved) return data in the same sequential sequence 0-1-2-3-4-5-6-7.
/// The difference onlu matters if fetching a cache line from memory in critical-ward-first order.

/// Mode register
/// Single data rate SDRAM has a single 10-bit programmable mode register. Later double-data-rate SDRAM standards add additional mode registers, addressed using the bank address pins.
/// For SDR SDRAM, the bank address pins and address lines A10 and above are ignored, but should be zero during a mode register write.
///
/// The bits are M9 through M0, presented on address lines A9 through A0 during a load mode register cycle.
/// -M9: Write burst mode. If 0, writes use the read burst length and mode. If 1, all writes are non-burst(single location).
/// -M8, M7: Operating mode. Reserved, and must be 00.
/// -M6, M5, M4: CAS latency. Generally only 010(CL2) and 011(CL3) are legal.Specifies the number of cycles between a read command and data output from the chip.
///  The chip has a fundamental limit on this value in nanoseconds; during initialization, the memory controller must use its knowledge of the clock frequency to translate that limit into cycles.
/// -M3: Burst type. 0-requests sequential burst ordering, while 1 requests interleaved burst ordering.
/// -M2, M1, M0: Burst length. Values of 000, 001, 010 and 011 specify a burst size of 1,2,4 or 8 words, respectively. Each read(adn write, if M9 is 0)will perform that many accesses, unless interrupted by a burst stop or other command.
///  A value of 111 specifies a full-row burst. The burst will continue until interrupted. Full-row bursts are only permitted with the sequential burst type.
///
/// Later DDR SDRAM standards use more mode register bits, and provide addtional mode registers called "extended mode registers". The register number is encoded on the bank address pins during the load mode register command.
/// For example. DDR2 SDRAM has a 13-bit mode register, a 13-bit extended mode register No.1(EMR1), and a 5-bit extended mode register No.2(EMR2).

/// Auto refresh
/// It is possible to refresh a RAM chip by opening and closing(activating and precharging) each row in each bank. However, to simplify the memory controller, SDRAM chips support an "auto refresh" command, which performs these operations to one row in each bank simultaneously.
/// The SDRAM also maintains an internal counter, which iterates over all possible rows. The memory controller must simply issue a sufficient number of auto refresh commands(one per row, 8192 in the example we have have using) every refresh interval(tREF=64ms is a common value).
/// All banks must be idle(closed, precharged) when this command is issued.

/// Low power modes
/// As mentioned, the clock enable(CKE) input can be used to  effectively stop the clock to an SDRAM.
/// The CKE input is sampled each rising edge of the clock, and if it is low, the following rising edge of the clock is ignored for all purposes other than checking CKE.
/// As long as CKE is low, it is permissible to change the clock rate, or even stop the clock entirely.
///
/// If CKE is lowered while the SDRAM is performing operations, it simply "freezes" in place until CKE is raised again.
///
/// If the SDRAM is idle(all banks precharged, no commands in process) when CKE is lowered, the SDRAM automatically enters power-down mode, consuming minimal power until CKE is raised again.
/// This must not last longer than the maximum refresh interval tREF, or memory contents may be lost. It is legal to stop the clock entirely during this time for additional power savings.
///
/// Finally, if CKE is lowered at the same time as an auto-refresh command is sent to the SDRAM, the SDRAM enters self-refresh mode. This is like power down, but the SDRAM uses an on-chip timer to generate internal refresh cycles as necessary.
/// The clock may be stopped during this time.
/// While self-refresh mode consumes slightly more power than power-down mode, it allows the memory controller to be disabled entirely, which commonly more than makes up the difference.
///
/// SDRAM designed for battery-powered devices offers some additional power-saving options.
/// One is temperature-dependent refresh; an on-chip temperature sensor reduces the refresh rate at lower temperatures, rather than always running it at the worst-case rate.
/// Another is selective refresh, which limits self-refresh to a portion of the DRAM array. The fraction which is refreshed is configured using an extended mode register.
/// The third, implemented in Mobile DDR(LPDDR) and LPDDR2 is "deep power down" mode, which invalidates the memory and requires a full reinitialization to exit from.
/// This is activated by sending a "burst terminate" command while lowering CKE.

/// DDR SDRAM prefetch architecture



localparam  [3:0]   S_RESET        = 4'd0,
                    S_IDLE         = 4'd1,
                    S_CLEARDLL     = 4'd2,
                    S_REFRESH      = 4'd3,
                    S_WPRE         = 4'd4,
                    S_WRITE        = 4'd5,
                    S_WRESP        = 4'd6,
                    S_WWAIT        = 4'd7,
                    S_RPRE         = 4'd8,
                    S_READ         = 4'd9,
                    S_RRESP        = 4'd10,
                    S_RWAIT        = 4'd11;

reg                             s_clk2                  ;
reg                             s_init_done             ;
reg     [2:0]                   s_ref_idle              ;
reg     [2:0]                   s_ref_real              ;
reg     [9:0]                   s_ref_cnt               ;
reg     [7:0]                   s_cnt                   ;

reg     [3:0]                   s_state                 ;

reg     [7:0]                   s_burst_len             ;
wire                            s_burst_last            ;
reg     [COL_BITS-2:0]          s_col_addr              ;

wire    [ROW_BITS-1:0]          s_ddr_a_col             ;

wire                            s_read_accessible       ;
wire                            s_read_respdone         ;
reg                             s_output_enable         ;
reg                             s_output_enable_d1      ;
reg                             s_output_enable_d2      ;

reg                             s_o_v_a                 ;
reg     [DQ_BITS-1:0]           s_o_dh_a                ;
reg     [DQ_BITS-1:0]           s_o_dl_a                ;
reg                             s_o_v_b                 ;
reg     [DQ_BITS-1:0]           s_o_dh_b                ;
reg                             s_o_dqs_c               ;
reg     [DQ_BITS-1:0]           s_o_d_c                 ;
reg     [DQ_BITS-1:0]           s_o_d_d                 ;

reg                             s_i_v_a                 ;
reg                             s_i_l_a                 ;
reg                             s_i_v_b                 ;
reg                             s_i_l_b                 ;
reg                             s_i_v_c                 ;
reg                             s_i_l_c                 ;
reg                             s_i_dqs_c               ;
reg     [DQ_BITS-1:0]           s_i_d_c                 ;
reg                             s_i_v_d                 ;
reg                             s_i_l_d                 ;
reg     [AXI_DW-1:0]            s_i_d_d                 ;
reg                             s_i_v_e                 ;
reg                             s_i_l_e                 ;
reg     [AXI_DW-1:0]            s_i_d_e                 ;

reg                             rstn_clk                ;
reg     [2:0]                   s_rstn_clk_tmp          ;
reg                             rstn_aclk               ;
reg     [2:0]                   s_rstn_aclk_tmp         ;

wire                            s_read_accessible       ;
wire                            s_read_respdone         ;
// -------------------------------------------------------------------------------------
//   constants defination and assignment
// -------------------------------------------------------------------------------------
localparam [ROW_BITS-1:0] DDR_A_DEFAULT      = 'b0100_0000_0000;
localparam [ROW_BITS-1:0] DDR_A_MR0          = 'b0001_0010_1001;
localparam [ROW_BITS-1:0] DDR_A_MR_CLEAR_DLL = 'b0000_0010_1001;

assign s_burst_last = (s_cnt[7:0] == s_burst_len[7:0]);

generate
    if(COL_BITS>10)
        assign s_ddr_a_col[ROW_BITS-1:0] = {s_col_addr[COL_BITS-2:9], s_burst_last, s_col_addr[8:0], 1'b0};
    else
        assign s_ddr_a_col[ROW_BITS-1:0] = {s_burst_last, s_col_addr[8:0], 1'b0};
endgenerate

// -------------------------------------------------------------------------------------
// generate reset sync with i_drv_clk
// -------------------------------------------------------------------------------------
always @ (posedge i_drv_clk or negedge i_rstn_async)
    if(~i_rstn_async)
        {rstn_clk, s_rstn_clk_tmp[2:0]} <= 4'b0;
    else
        {rstn_clk, s_rstn_clk_tmp[2:0]} <= {s_rstn_clk_tmp[2:0], 1'b1};

// -------------------------------------------------------------------------------------
//   generate clocks
// -------------------------------------------------------------------------------------
always @ (posedge i_drv_clk or negedge rstn_clk)
    if(~rstn_clk)
        {clk, s_clk2}   <= 2'b00;
    else
        {clk, s_clk2}   <= {clk, s_clk2} + 2'b01;
    
// -------------------------------------------------------------------------------------
// generate reset sync with clk
// -------------------------------------------------------------------------------------
always @ (posedge clk or negedge i_rstn_async)
    if(~i_rstn_async)
        {rstn_aclk, s_rstn_aclk_tmp[2:0]} <= 4'b0;
    else
        {rstn_aclk, s_rstn_aclk_tmp[2:0]} <= {s_rstn_aclk_tmp[2:0], 1'b1};

// -------------------------------------------------------------------------------------
//   generate user reset
// -------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn_aclk)
    if(~rstn_aclk)
        rst_n <= 1'b0;
    else
        rst_n <= s_init_done;

// -------------------------------------------------------------------------------------
//   refresh wptr self increasement
// -------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn_aclk)
begin
    if(~rstn_aclk)
        begin
            s_ref_cnt[9:0]  <= 10'd0;
            s_ref_idle[2:0] <= 3'd1;
        end
    else if(s_init_done)
        begin
            if(s_ref_cnt[9:0] < tREFC)
                begin
                    s_ref_cnt[9:0]  <= s_ref_cnt[9:0] + 10'd1;
                    s_ref_idle[2:0] <= s_ref_idle[2:0];
                end
            else
                begin
                    s_ref_cnt[9:0]  <= 10'd0;
                    s_ref_idle[2:0] <= s_ref_idle[2:0] + 3'd1;
                end
        end
    /// else hold
end

// -------------------------------------------------------------------------------------
//   generate DDR clock
// -------------------------------------------------------------------------------------
assign o_ddr_ck_p = ~clk;
assign o_ddr_ck_n = clk;
assign o_ddr_cke  = ~o_ddr_cs_n;

// -------------------------------------------------------------------------------------
//   generate DDR DQ output behavior
// -------------------------------------------------------------------------------------
assign o_ddr_dm     [DM_BITS-1:0]   = s_output_enable ? {DM_BITS{1'b0}}       : {DM_BITS{1'bz}};
assign io_ddr_dqs   [DQS_BITS-1:0]  = s_output_enable ? {DQS_BITS{s_o_dqs_c}} : {DQS_BITS{1'bz}};
assign io_ddr_dq    [DQ_BITS-1:0]   = s_output_enable ? s_o_d_d               : {DQ_BITS{1'bz}};

// -------------------------------------------------------------------------------------
//  assignment for user interface (AXI4)
// -------------------------------------------------------------------------------------
assign o_awready = s_state==S_IDLE && s_init_done && s_ref_real[2:0]==s_ref_idle[2:0];
assign o_wready  = s_state==S_WRITE;
assign o_bvalid  = s_state==S_WRESP;
assign o_arready = s_state==S_IDLE && s_init_done && s_ref_real[2:0]==s_ref_idle[2:0] && ~i_awvalid && s_read_accessible;

// -------------------------------------------------------------------------------------
//   main FSM for generating DDR-SDRAM behavior
// -------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn_aclk)
    if(~rstn_aclk)
        begin
            o_ddr_cs_n      <= 1'b1;
            o_ddr_ras_n     <= 1'b1;
            o_ddr_cas_n     <= 1'b1;
            o_ddr_we_n      <= 1'b1;
            o_ddr_ba        <= 0;
            o_ddr_a         <= DDR_A_DEFAULT;
            s_col_addr      <= 0;
            s_burst_len     <= 8'd0;
            s_init_done     <= 1'b0;
            s_ref_real[2:0] <= 3'd0;
            s_cnt           <= 8'd0;
            s_state         <= S_RESET;
    end
    else begin
        case(s_state)
            S_RESET:
                begin
                    s_cnt <= s_cnt + 8'd1;
                    if(s_cnt<8'd13)
                        begin

                        end
                    else if(s_cnt<8'd50)
                        begin
                            o_ddr_cs_n  <= 1'b0;
                        end
                    else if(s_cnt<8'd51)
                        begin
                            o_ddr_ras_n <= 1'b0;
                            o_ddr_we_n  <= 1'b0;
                        end
                    else if(s_cnt<8'd53)
                        begin
                            o_ddr_ras_n <= 1'b1;
                            o_ddr_we_n  <= 1'b1;
                        end
                    else if(s_cnt<8'd54)
                        begin
                            o_ddr_ras_n <= 1'b0;
                            o_ddr_cas_n <= 1'b0;
                            o_ddr_we_n  <= 1'b0;
                            o_ddr_ba    <= 1;
                            o_ddr_a     <= 0;
                        end
                    else
                        begin
                            o_ddr_ba    <= 0;
                            o_ddr_a     <= DDR_A_MR0;
                            s_state     <= S_IDLE;
                        end
                end

            S_IDLE:
                begin
                o_ddr_ras_n <= 1'b1;
                o_ddr_cas_n <= 1'b1;
                o_ddr_we_n  <= 1'b1;
                o_ddr_ba    <= 0;
                o_ddr_a     <= DDR_A_DEFAULT;
                s_cnt       <= 8'd0;
                if(s_ref_real[2:0] != s_ref_idle[2:0])
                    begin
                        s_ref_real[2:0] <= s_ref_real[2:0] + 3'd1;
                        s_state <= S_REFRESH;
                    end
                else if(~s_init_done)
                    begin
                        s_state <= S_CLEARDLL;
                    end
                else if(i_awvalid)
                    begin
                        o_ddr_ras_n <= 1'b0;
                        {o_ddr_ba, o_ddr_a, s_col_addr} <= i_awaddr[AXI_AW-1:DQ_LEVEL];
                        s_burst_len <= i_awlen;
                        s_state <= S_WPRE;
                    end
                else if(i_arvalid & s_read_accessible)
                    begin
                        o_ddr_ras_n <= 1'b0;
                        {o_ddr_ba, o_ddr_a, s_col_addr} <= i_araddr[AXI_AW-1:DQ_LEVEL];
                        s_burst_len <= i_arlen;
                        s_state <= S_RPRE;
                    end
                end

            S_CLEARDLL:
                begin
                    o_ddr_ras_n <= s_cnt!=8'd0;
                    o_ddr_cas_n <= s_cnt!=8'd0;
                    o_ddr_we_n <= s_cnt!=8'd0;
                    o_ddr_a <= s_cnt!=8'd0 ? DDR_A_DEFAULT : DDR_A_MR_CLEAR_DLL;
                    s_cnt <= s_cnt + 8'd1;
                if(s_cnt==8'd255)
                    begin
                        s_init_done <= 1'b1;
                        s_state <= S_IDLE;
                    end
                end

            S_REFRESH:
                begin
                    s_cnt <= s_cnt + 8'd1;
                    if(s_cnt<8'd1)
                        begin
                            o_ddr_ras_n <= 1'b0;
                            o_ddr_we_n <= 1'b0;
                        end
                    else if(s_cnt<8'd3)
                        begin
                            o_ddr_ras_n <= 1'b1;
                            o_ddr_we_n <= 1'b1;
                        end
                    else if(s_cnt<8'd4)
                        begin
                            o_ddr_ras_n <= 1'b0;
                            o_ddr_cas_n <= 1'b0;
                        end
                    else if(s_cnt<8'd10)
                        begin
                            o_ddr_ras_n <= 1'b1;
                            o_ddr_cas_n <= 1'b1;
                        end
                    else if(s_cnt<8'd11)
                        begin
                            o_ddr_ras_n <= 1'b0;
                            o_ddr_cas_n <= 1'b0;
                        end
                    else if(s_cnt<8'd17)
                        begin
                            o_ddr_ras_n <= 1'b1;
                            o_ddr_cas_n <= 1'b1;
                        end
                    else
                        begin
                            s_state <= S_IDLE;
                        end
                end

            S_WPRE:
                begin
                    o_ddr_ras_n <= 1'b1;
                    s_cnt       <= 8'd0;
                    s_state     <= S_WRITE;
                end

            S_WRITE:
                begin
                    o_ddr_a <= s_ddr_a_col;
                    if(i_wvalid)
                        begin
                            o_ddr_cas_n <= 1'b0;
                            o_ddr_we_n  <= 1'b0;
                            s_col_addr  <= s_col_addr + {{(COL_BITS-2){1'b0}}, 1'b1};
                            if(s_burst_last | i_wlast)
                                begin
                                    s_cnt   <= 8'd0;
                                    s_state <= S_WRESP;
                                end
                            else
                                begin
                                    s_cnt   <= s_cnt + 8'd1;
                                end
                        end
                    else
                        begin
                            o_ddr_cas_n <= 1'b1;
                            o_ddr_we_n  <= 1'b1;
                        end
                end

            S_WRESP:
                begin
                    o_ddr_cas_n <= 1'b1;
                    o_ddr_we_n  <= 1'b1;
                    s_cnt       <= s_cnt + 8'd1;
                    if(i_bready)
                        s_state <= S_WWAIT;
                end

            S_WWAIT:
                begin
                    s_cnt <= s_cnt + 8'd1;
                    if(s_cnt>=tW2I)
                        s_state <= S_IDLE;
                end

            S_RPRE:
                begin
                    o_ddr_ras_n <= 1'b1;
                    s_cnt       <= 8'd0;
                    s_state     <= S_READ;
                end

            S_READ:
                begin
                    o_ddr_cas_n <= 1'b0;
                    o_ddr_a     <= s_ddr_a_col;
                    s_col_addr  <= s_col_addr + {{(COL_BITS-2){1'b0}}, 1'b1};
                    if(s_burst_last)
                        begin
                            s_cnt <= 8'd0;
                            s_state <= S_RRESP;
                        end
                    else
                        begin
                            s_cnt <= s_cnt + 8'd1;
                        end
                end

            S_RRESP:
                begin
                    o_ddr_cas_n <= 1'b1;
                    s_cnt       <= s_cnt + 8'd1;
                    if(s_read_respdone)
                        s_state <= S_RWAIT;
                end

            S_RWAIT:
                begin
                    s_cnt <= s_cnt + 8'd1;
                    if(s_cnt>=tR2I)
                        s_state <= S_IDLE;
                end

            default: s_state <= S_IDLE;
        endcase
    end

// -------------------------------------------------------------------------------------
//   output enable generate
// -------------------------------------------------------------------------------------
always @ (posedge clk or negedge rst_n)
    if(~rst_n)
        begin
            s_output_enable     <= 1'b0;
            s_output_enable_d1  <= 1'b0;
            s_output_enable_d2  <= 1'b0;
        end
    else
        begin
            s_output_enable     <= s_state==S_WRITE || s_output_enable_d1 || s_output_enable_d2;
            s_output_enable_d1  <= s_state==S_WRITE;
            s_output_enable_d2  <= s_output_enable_d1;
        end

// -------------------------------------------------------------------------------------
//   output data latches --- stage A
// -------------------------------------------------------------------------------------
always @ (posedge clk or negedge rst_n)
    if(~rst_n)
        begin
            s_o_v_a <= 1'b0;
            {s_o_dh_a[DQ_BITS-1:0], s_o_dl_a[DQ_BITS-1:0]} <= {AXI_DW{1'b0}};
        end
    else
        begin
            s_o_v_a <= (s_state==S_WRITE && i_wvalid);
            {s_o_dh_a[DQ_BITS-1:0], s_o_dl_a[DQ_BITS-1:0]} <= i_wdata[AXI_DW-1:0];
        end

// -------------------------------------------------------------------------------------
//   output data latches --- stage B
// -------------------------------------------------------------------------------------
always @ (posedge clk or negedge rst_n)
    if(~rst_n)
        begin
            s_o_v_b                 <= 1'b0;
            s_o_dh_b[DQ_BITS-1:0]   <= {DQ_BITS{1'b0}};
        end
    else
        begin
            s_o_v_b                 <= s_o_v_a;
            s_o_dh_b[DQ_BITS-1:0]   <= s_o_dh_a[DQ_BITS-1:0];
        end

// -------------------------------------------------------------------------------------
//   dq and dqs generate for output (write)
// -------------------------------------------------------------------------------------
always @ (posedge s_clk2)
    if (~clk)
        begin
            s_o_dqs_c <= 1'b0;
        end
    else
        begin
            s_o_dqs_c <= s_o_v_b;
        end

always @ (posedge s_clk2)
    if (~clk)
        begin
            if (s_o_v_a)
                s_o_d_c[DQ_BITS-1:0] <= s_o_dl_a[DQ_BITS-1:0];
            else
                s_o_d_c[DQ_BITS-1:0] <= {DQ_BITS{1'b0}};
        end
    else
        begin
            if (s_o_v_b)
                s_o_d_c[DQ_BITS-1:0] <= s_o_dh_b[DQ_BITS-1:0];
            else
                s_o_d_c[DQ_BITS-1:0] <= {DQ_BITS{1'b0}};
        end

// -------------------------------------------------------------------------------------
//   dq delay for output (write)
// -------------------------------------------------------------------------------------
always @ (posedge i_drv_clk)
    s_o_d_d[DQ_BITS-1:0]    <= s_o_d_c[DQ_BITS-1:0];

// -------------------------------------------------------------------------------------
//   dq sampling for input (read)
// -------------------------------------------------------------------------------------
always @ (posedge s_clk2)
begin
    s_i_dqs_c               <= io_ddr_dqs[DQS_BITS-1:0];
    s_i_d_c[DQ_BITS-1:0]    <= io_ddr_dq[DQ_BITS-1:0];
end

always @ (posedge s_clk2)
    if(s_i_dqs_c)
        s_i_d_d[AXI_DW-1:0] <= {io_ddr_dq[DQ_BITS-1:0], s_i_d_c[DQ_BITS-1:0]};

always @ (posedge clk or negedge rst_n)
    if(~rst_n)
        begin
            {s_i_v_a, s_i_v_b, s_i_v_c, s_i_v_d} <= 0;
            {s_i_l_a, s_i_l_b, s_i_l_c, s_i_l_d} <= 0;
        end
    else
        begin
            s_i_v_a <= s_state==S_READ;
            s_i_l_a <= s_burst_last;
            s_i_v_b <= s_i_v_a;
            s_i_l_b <= s_i_l_a & s_i_v_a;
            s_i_v_c <= s_i_v_b;
            s_i_l_c <= s_i_l_b;
            s_i_v_d <= s_i_v_c;
            s_i_l_d <= s_i_l_c;
        end

always @ (posedge clk or negedge rst_n)
    if(~rst_n)
        begin
            s_i_v_e             <= 1'b0;
            s_i_l_e             <= 1'b0;
            s_i_d_e[AXI_DW-1:0] <= {AXI_DW{1'b0}};
        end
    else
        begin
            s_i_v_e             <= s_i_v_d;
            s_i_l_e             <= s_i_l_d;
            s_i_d_e[AXI_DW-1:0] <= s_i_d_d[AXI_DW-1:0];
        end

// -------------------------------------------------------------------------------------
//   data buffer for read
// -------------------------------------------------------------------------------------
assign o_rvalid             = s_i_v_e;
assign o_rlast              = s_i_l_e;
assign o_rdata[AXI_DW-1:0]  = s_i_d_e[AXI_DW-1:0];

assign s_read_accessible = 1'b1;
assign s_read_respdone   = s_i_l_e;

endmodule
