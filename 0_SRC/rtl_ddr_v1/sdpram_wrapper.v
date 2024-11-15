`timescale 1ns / 1ps

module sdpram_wrapper #(
    parameter   DEPTH               = 32                                    ,   // depth
    parameter   DW                  = 32                                    ,   // data width
    parameter   AW                  = $clog2(DEPTH)>0 ? $clog2(DEPTH) : 1   ,   // depth 32 -> addr 5?at least 1
    parameter   BYTE_WRITE_WIDTH_A  = DW                                    ,   // BYTE WRITE WIDTH for port-A, if BYTE_WRITE_WIDTH_A is DW, means disable BYTE Write
    parameter   READ_LATENCY_B      = 1                                     ,
    parameter   WRITE_MODE_B        = "no_change"                           ,   // no_change, read_first, write_first. Default value = no_change.
    parameter   MEMORY_TYPE         = "block"                               ,   // "auto"  "block"  "distributed"  "ultra"- URAM
    parameter   CLOCKING_MODE       = "common_clock"                        ,   // "common_clock"   "independent_clock",  Default value = "common_clock".
    parameter   INIT_FILE           = "none"                                    // "none"--> not use init file
    )
    (
    // clk & rst
    input   wire                                    clka                                    ,
    input   wire                                    clkb                                    ,
    input   wire                                    rst                                     ,
    // write port
    input   wire                                    i_ena                                   ,
    input   wire    [AW  -1 : 0]                    i_addra                                 ,
    input   wire    [DW  -1 : 0]                    i_dina                                  ,
    input   wire    [DW/BYTE_WRITE_WIDTH_A-1:0]     i_wea                                   ,
    // read port
    input   wire                                    i_enb                                   ,
    input   wire    [AW  -1 : 0]                    i_addrb                                 ,
    output  wire    [DW  -1 : 0]                    o_doutb
    );

/// ram instance
generate
        cm_ram_simple_dual_one_clock #(
            .WIDTH                  ( DW                            ),
            .SIZE                   ( $clog2(DEPTH)                 )
            )
            u_cm_ram_simple_dual_one_clock
            (
            .clk                    ( clka                          ),
            .ena                    ( i_ena                         ),
            .enb                    ( i_enb                         ),
            .wea                    ( i_ena                         ),
            .addra                  ( i_addra                       ),
            .addrb                  ( i_addrb                       ),
            .dia                    ( i_dina                        ),
            .dob                    ( o_doutb                       )
            );

endgenerate

endmodule
