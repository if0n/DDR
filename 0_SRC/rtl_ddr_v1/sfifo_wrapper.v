`timescale 1ns / 1ps

module sfifo_wrapper #(
   parameter   DEPTH              = 32                            ,  // depth, must be power of two
   parameter   DW                 = 32                            ,  // data width
   parameter   FIFO_MEMORY_TYPE   = "block"                       ,
   parameter   READ_MODE          = "fwft"                        ,  // "std" // "fwft"- First-Word-Fall-Through read mode                                                                         |
   parameter   FIFO_READ_LATENCY  = 0                             ,  // If READ_MODE = "fwft", then the only applicable value is 0
   parameter   PROG_EMPTY_THRESH  = 10                            ,
   parameter   PROG_FULL_THRESH   = 22
   )
   (
   /// clk & rst--------------------------------------------------
   input    wire                            wr_clk                     ,
   input    wire                            rst                        ,
   /// write port-------------------------------------------------
   input    wire                            i_wr_en                    ,
   input    wire    [DW  -1 : 0]            i_din                      ,
   /// read port--------------------------------------------------
   input    wire                            i_rd_en                    ,
   output   wire    [DW  -1 : 0]            o_dout                     ,
   /// status-----------------------------------------------------
   output   wire                            o_wr_rst_busy              ,
   output   wire                            o_rd_rst_busy              ,

   output   wire                            o_empty                    ,
   output   wire                            o_full                     ,

   output   wire                            o_pempty                   ,
   output   wire                            o_pfull                    ,

   output   wire    [$clog2(DEPTH) : 0]     o_wdata_cnt                ,
   output   wire    [$clog2(DEPTH) : 0]     o_rdata_cnt                ,

   output   wire                            o_overflow                 ,
   output   wire                            o_underflow
   );


wire                            wr_en               ;
wire [$clog2(DEPTH) - 1:0]      waddr               ;
wire [DW - 1:0]                 wdata               ;

wire                            rd_en               ;
wire [$clog2(DEPTH) - 1:0]      raddr               ;
wire [DW - 1:0]                 rdata               ;

/// fifo inst
cm_vr_sfifo_ctrl_wrapper #(
   .WIDTH_DATA          ( DW                    ),
   .WIDTH_ADDR          ( $clog2(DEPTH)         ),
   .WATERRAGE_UP        ( DEPTH-PROG_FULL_THRESH),
   .WATERRAGE_DOWN      ( PROG_EMPTY_THRESH     ),
   .SHOW_AHEAD          ( READ_MODE == "fwft"   )
   )
   u_cm_vr_sfifo_ctrl_wrapper
   (
   .clk                 ( wr_clk                ),
   .rst_n               ( !rst                  ),
   .clr                 ( 1'b0                  ),

   .wr_en               ( i_wr_en               ),
   .wr_data             ( i_din                 ),
   .full                ( o_full                ),

   .rd_en               ( i_rd_en               ),
   .rd_dout             ( o_dout                ),
   .empty               ( o_empty               ),

   .alfull              ( o_pfull               ),
   .alempty             ( o_pempty              ),

   .ram_wen             ( wr_en                 ),
   .ram_wdata           ( wdata                 ),
   .ram_waddr           ( waddr                 ),
   .ram_ren             ( rd_en                 ),
   .ram_raddr           ( raddr                 ),
   .ram_rdata           ( rdata                 )
   );

assign o_overflow = o_full && i_wr_en;
assign o_underflow = o_empty && i_rd_en;

assign o_wr_rst_busy = 1'b0;
assign o_rd_rst_busy = 1'b0;

assign o_wdata_cnt = {($clog2(DEPTH)+1){1'b0}};
assign o_rdata_cnt = {($clog2(DEPTH)+1){1'b0}};

/// ram instance
sdpram_wrapper #(
    .DEPTH                  ( DEPTH                         ),   // depth
    .DW                     ( DW                            ),   // data width
    .READ_LATENCY_B         ( 1                             ),
    .WRITE_MODE_B           ( "no_change"                   )    // no_change, read_first, write_first. Default value = no_change.
    )
    u_sdpram_wrapper
    (
    // clk & rst
    .clka                   ( wr_clk                        ),
    .clkb                   ( wr_clk                        ),
    .rst                    ( rst                           ),
    // write port
    .i_ena                  ( wr_en                         ),
    .i_addra                ( waddr                         ),
    .i_dina                 ( wdata                         ),
    .i_wea                  ( wr_en                         ),
    // read port
    .i_enb                  ( rd_en                         ),
    .i_addrb                ( raddr                         ),
    .o_doutb                ( rdata                         )
    );


endmodule
