
//--------------------------------------------------------------------------------------------------------
// Module  : tb_ddr_sdram_ctrl
// Type    : simulation, top
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: testbench for ddr_sdram_ctrl
//--------------------------------------------------------------------------------------------------------

`timescale 1ps/1ps

module tb_ddr_sdram_ctrl();

// -------------------------------------------------------------------------------------
//   self test error signal, 1'b1 indicates error
// -------------------------------------------------------------------------------------
wire               error;

// -----------------------------------------------------------------------------------------------------------------------------
// simulation control
// -----------------------------------------------------------------------------------------------------------------------------
initial
begin: fsdbdump
    string fsdb_name;
    fsdb_name = "tb_ddr_sdram_ctrl.fsdb";
    $fsdbDumpfile(fsdb_name);
    $fsdbDumpvars;
    $fsdbDumpMDA();
end

initial begin
    #200000000;              // simulation for 200us
    if(error)
        $display("*** Error: there are mismatch when read out and compare!!! see wave for detail.");
    else
        $display("validation successful !!");
    $finish;
end

// -------------------------------------------------------------------------------------
//   DDR-SDRAM parameters
// -------------------------------------------------------------------------------------
localparam  BA_BITS  = 2;
localparam  ROW_BITS = 13;
localparam  COL_BITS = 11;
localparam  DQ_LEVEL = 1;

localparam  DQ_BITS  = (4<<DQ_LEVEL);
localparam  DQS_BITS = ((1<<DQ_LEVEL)+1)/2;

// -------------------------------------------------------------------------------------
//   AXI4 burst length parameters
// -------------------------------------------------------------------------------------
localparam [7:0] WBURST_LEN = 8'd7;
localparam [7:0] RBURST_LEN = 8'd7;

// -------------------------------------------------------------------------------------
//   AXI4 parameters
// -------------------------------------------------------------------------------------
localparam  AW = BA_BITS+ROW_BITS+COL_BITS+DQ_LEVEL-1;
localparam  DW = (8<<DQ_LEVEL);

// -------------------------------------------------------------------------------------
//   driving clock and reset generate
// -------------------------------------------------------------------------------------
reg rstn_async=1'b0, clk300m=1'b1;
always #1667 clk300m = ~clk300m;
initial begin repeat(4) @(posedge clk300m); rstn_async<=1'b1; end

// -------------------------------------------------------------------------------------
//   DDR-SDRAM signal
// -------------------------------------------------------------------------------------
wire                ddr_ck_p, ddr_ck_n;
wire                ddr_cke;
wire                ddr_cs_n, ddr_ras_n, ddr_cas_n, ddr_we_n;
wire [         1:0] ddr_ba;
wire [ROW_BITS-1:0] ddr_a;
wire [DQS_BITS-1:0] ddr_dm;
tri  [DQS_BITS-1:0] ddr_dqs;
tri  [ DQ_BITS-1:0] ddr_dq;

// -------------------------------------------------------------------------------------
//   AXI4 interface
// -------------------------------------------------------------------------------------
wire               rstn;
wire               clk;
wire               awvalid;
wire               awready;
wire [AW-1:0]      awaddr;
wire [        7:0] awlen;
wire               wvalid;
wire               wready;
wire               wlast;
wire [DW-1:0]      wdata;
wire               bvalid;
wire               bready;
wire               arvalid;
wire               arready;
wire [AW-1:0]      araddr;
wire [        7:0] arlen;
wire               rvalid;
wire               rready;
wire               rlast;
wire [DW-1:0]      rdata;

// -------------------------------------------------------------------------------------
//   AXI4 master for testing
// -------------------------------------------------------------------------------------
axi_self_test_master #(
    .AW_TEST        ( 12          ),
    .AW             ( AW          ),
    .DW             ( DW          ),
    .D_LEVEL        ( DQ_LEVEL    ),
    .WBURST_LEN     ( WBURST_LEN  ),
    .RBURST_LEN     ( RBURST_LEN  )
) axi_m_i (
    .rst_n          ( rstn        ),
    .clk            ( clk         ),

    .o_awvalid     ( awvalid     ),
    .i_awready     ( awready     ),
    .o_awaddr      ( awaddr      ),
    .o_awlen       ( awlen       ),
    .o_wvalid      ( wvalid      ),
    .i_wready      ( wready      ),
    .o_wlast       ( wlast       ),
    .o_wdata       ( wdata       ),
    .i_bvalid      ( bvalid      ),
    .o_bready      ( bready      ),
    .o_arvalid     ( arvalid     ),
    .i_arready     ( arready     ),
    .o_araddr      ( araddr      ),
    .o_arlen       ( arlen       ),
    .i_rvalid      ( rvalid      ),
    .o_rready      ( rready      ),
    .i_rlast       ( rlast       ),
    .i_rdata       ( rdata       ),

    .o_error       ( error       ),
    .o_error_cnt   (             )
);

// -------------------------------------------------------------------------------------
//   DDR-SDRAM controller
// -------------------------------------------------------------------------------------
ddr_sdram_ctrl #(
    .READ_BUFFER    ( 0           ),
    .BA_BITS        ( BA_BITS     ),    /// 2
    .ROW_BITS       ( ROW_BITS    ),    /// 13
    .COL_BITS       ( COL_BITS    ),    /// 11
    .DQ_LEVEL       ( DQ_LEVEL    ),    /// 1
    .tREFC          ( 10'd512     ),
    .tW2I           ( 8'd6        ),
    .tR2I           ( 8'd6        )
) ddr_sdram_ctrl_i (
    .i_rstn_async   ( rstn_async  ),
    .i_drv_clk      ( clk300m     ),

    .rst_n          ( rstn        ),
    .clk            ( clk         ),

    .i_awvalid      ( awvalid     ),
    .o_awready      ( awready     ),
    .i_awaddr       ( awaddr      ),
    .i_awlen        ( awlen       ),
    .i_wvalid       ( wvalid      ),
    .o_wready       ( wready      ),
    .i_wlast        ( wlast       ),
    .i_wdata        ( wdata       ),
    .o_bvalid       ( bvalid      ),
    .i_bready       ( bready      ),
    .i_arvalid      ( arvalid     ),
    .o_arready      ( arready     ),
    .i_araddr       ( araddr      ),
    .i_arlen        ( arlen       ),
    .o_rvalid       ( rvalid      ),
    .i_rready       ( rready      ),
    .o_rlast        ( rlast       ),
    .o_rdata        ( rdata       ),

    .o_ddr_ck_p     ( ddr_ck_p    ),
    .o_ddr_ck_n     ( ddr_ck_n    ),
    .o_ddr_cke      ( ddr_cke     ),
    .o_ddr_cs_n     ( ddr_cs_n    ),
    .o_ddr_ras_n    ( ddr_ras_n   ),
    .o_ddr_cas_n    ( ddr_cas_n   ),
    .o_ddr_we_n     ( ddr_we_n    ),
    .o_ddr_ba       ( ddr_ba      ),
    .o_ddr_a        ( ddr_a       ),
    .o_ddr_dm       ( ddr_dm      ),
    .io_ddr_dqs     ( ddr_dqs     ),
    .io_ddr_dq      ( ddr_dq      )
);

// -------------------------------------------------------------------------------------
//  MICRON DDR-SDRAM simulation model
// -------------------------------------------------------------------------------------
micron_ddr_sdram_model #(
    .BA_BITS     ( BA_BITS     ),   /// 2
    .ROW_BITS    ( ROW_BITS    ),   /// 13
    .COL_BITS    ( COL_BITS    ),   /// 11
    .DQ_LEVEL    ( DQ_LEVEL    )    /// 1
) ddr_model_i (
    .Clk         ( ddr_ck_p    ),   /// clk
    .Clk_n       ( ddr_ck_n    ),   /// clk
    .Cke         ( ddr_cke     ),   /// clock enable
    .Cs_n        ( ddr_cs_n    ),   /// chip select
    .Ras_n       ( ddr_ras_n   ),   /// row address select
    .Cas_n       ( ddr_cas_n   ),   /// col address select
    .We_n        ( ddr_we_n    ),   /// write enable
    .Ba          ( ddr_ba      ),   /// bank address
    .Addr        ( ddr_a       ),   /// address
    .Dm          ( ddr_dm      ),   /// data mask
    .Dqs         ( ddr_dqs     ),   /// data strobe
    .Dq          ( ddr_dq      )    /// data
);

endmodule
