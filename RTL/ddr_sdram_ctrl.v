
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
///                                                                     The most significant settings are CAS latency(2 or 3 cycles) and burst lenggth(1,2,4 or 8 cycles)

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
/// Both read and write commands require a column address. Because each chip accesses 8 bits of date a time

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
