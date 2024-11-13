
//--------------------------------------------------------------------------------------------------------
// Module  : axi_self_test_master
// Type    : synthesizable
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: write increase data to AXI4 slave,
//           then read data and check whether they are increasing
//--------------------------------------------------------------------------------------------------------

module axi_self_test_master #(
    parameter                   AW_TEST         = 26    ,
    parameter                   AW              = 26    ,
    parameter                   DW              = 16    ,
    parameter                   D_LEVEL         = 1     ,
    parameter   [7:0]           WBURST_LEN      = 8'd7  ,
    parameter   [7:0]           RBURST_LEN      = 8'd7
)(
    input  wire                         rst_n           ,
    input  wire                         clk             ,

    output wire                         o_awvalid       ,
    input  wire                         i_awready       ,
    output reg      [AW-1:0]            o_awaddr        ,
    output wire     [7:0]               o_awlen         ,
    output wire                         o_wvalid        ,
    input  wire                         i_wready        ,
    output wire                         o_wlast         ,
    output wire     [DW-1:0]            o_wdata         ,
    input  wire                         i_bvalid        ,
    output wire                         o_bready        ,

    output wire                         o_arvalid       ,
    input  wire                         i_arready       ,
    output reg      [AW-1:0]            o_araddr        ,
    output wire     [7:0]               o_arlen         ,
    input  wire                         i_rvalid        ,
    output wire                         o_rready        ,
    input  wire                         i_rlast         ,
    input  wire     [DW-1:0]            i_rdata         ,

    output reg                          o_error         ,
    output reg      [15:0]              o_error_cnt
);

///
localparam  [AW:0]     ADDR_INC =  (1<<D_LEVEL)    ;
/// -------------------------------------------------------------
localparam  [2:0]       S_INIT  = 3'd0  ,
                        S_AW    = 3'd1  ,
                        S_W     = 3'd2  ,
                        S_B     = 3'd3  ,
                        S_AR    = 3'd4  ,
                        S_R     = 3'd5  ;
/// -------------------------------------------------------------
reg     [3:0]           s_state                 ;
wire                    s_aw_end                ;
reg                     s_awaddr_carry          ;
reg     [7:0]           s_w_cnt                 ;

wire    [AW:0]          s_araddr_next           ;

wire    [DW-1:0]        s_rdata_idle            ;
/// -------------------------------------------------------------
///
assign o_awvalid        = s_state == S_AW;
assign o_awlen[7:0]     = WBURST_LEN;

assign o_wvalid         = s_state == S_W;
assign o_wlast          = s_w_cnt[7:0] == WBURST_LEN;
assign o_wdata[DW-1:0]  = o_awaddr[DW-1:0];

assign o_bready         = 1'b1;

assign o_arvalid        = s_state == S_AR;
assign o_arlen[7:0]     = RBURST_LEN;

assign o_rready         = 1'b1;
///
assign s_araddr_next[AW:0] = {1'b0, o_araddr[AW-1:0]} + ADDR_INC;

assign s_aw_end = (AW_TEST < AW) ? o_awaddr[AW_TEST] : s_awaddr_carry;


always @ (posedge clk or negedge rst_n)
    if(!rst_n)
        begin
            o_awaddr[AW-1:0]    <= {AW{1'b0}};
            s_awaddr_carry      <= 1'b0;
            s_w_cnt[7:0]        <= 8'd0;
            o_araddr[AW-1:0]    <= {AW{1'b0}};
            s_state             <= S_INIT;
        end
    else begin
        case(s_state)
            ///
            S_INIT:
                begin
                    o_awaddr[AW-1:0]    <= {AW{1'b0}};
                    s_awaddr_carry      <= 1'b0;
                    s_w_cnt[7:0]        <= 8'd0;
                    o_araddr[AW-1:0]    <= {AW{1'b0}};
                    s_state             <= S_AW;
                end
            ///
            S_AW:
                if(i_awready)
                    begin
                        s_w_cnt[7:0]    <= 8'd0;
                        s_state         <= S_W;
                    end
            ///
            S_W:
                if(i_wready)
                    begin
                        {s_awaddr_carry, o_awaddr[AW-1:0]}  <= {s_awaddr_carry, o_awaddr[AW-1:0]} + ADDR_INC;
                        s_w_cnt[7:0]    <= s_w_cnt[7:0] + 8'd1;
                        if(o_wlast)
                            s_state <= S_B;
                    end
            ///
            S_B:
                if(i_bvalid)
                    s_state <= s_aw_end ? S_AR : S_AW;
            ///
            S_AR:
                if(i_arready)
                    s_state <= S_R;
            ///
            S_R:
                if(i_rvalid)
                    begin
                        o_araddr[AW-1:0] <= s_araddr_next[AW-1:0];
                        if(i_rlast)
                        begin
                            s_state <= S_AR;
                            if(s_araddr_next[AW_TEST])
                                o_araddr[AW-1:0] <= {AW{1'b0}};
                        end
                    end
        endcase
    end

// ------------------------------------------------------------
//  read and write mismatch detect
// ------------------------------------------------------------
assign s_rdata_idle[DW-1:0] = o_araddr[DW-1:0];

always @ (posedge clk or negedge rst_n)
begin
    if(~rst_n)
        o_error   <= 1'b0;
    else
        o_error   <= i_rvalid && o_rready && (i_rdata[DW-1:0] != s_rdata_idle[DW-1:0]);
end

always @ (posedge clk or negedge rst_n)
begin
    if(~rst_n)
        o_error_cnt[15:0]   <= 16'd0;
    else if(o_error)
        o_error_cnt[15:0]   <= o_error_cnt[15:0] + 16'd1;
    /// else hold
end

endmodule
