`timescale 1ns / 1ps
/// block=====================================================================================
/// clk & rst_n
wire    clk     ;
wire    rst_n   ;

assign clk      = tb_yuf.u_fd_ack_wrapper.sys_clk;
assign rst_n    = tb_yuf.u_fd_ack_wrapper.sys_rstn;


/// fd_ack_wrapper
wire                                s_p_ack_gather_fifo_rdy             ;
wire                                s_p_ack_gather_fifo_vld             ;
wire        [288-1:0]               s_p_ack_gather_fifo_data            ;

assign s_p_ack_gather_fifo_rdy              = tb_yuf.u_fd_ack_wrapper.o_ack_gather_fifo_rdy;
assign s_p_ack_gather_fifo_vld              = tb_yuf.u_fd_ack_wrapper.i_ack_gather_fifo_vld;
assign s_p_ack_gather_fifo_data[288-1:0]    = tb_yuf.u_fd_ack_wrapper.i_ack_gather_fifo_data[287:0];

/// sqe data
integer sim_fd_ack_wrapper_in;
initial
begin
    sim_fd_ack_wrapper_in = $fopen("../nv_script/data/out/sim_fd_ack_wrapper_in.txt", "w");
end
always @(posedge clk)
begin
    if(s_p_ack_gather_fifo_rdy && s_p_ack_gather_fifo_vld)
        begin
            $fdisplay(
                sim_fd_ack_wrapper_in,
                "%h, %h, %h",
                s_p_ack_gather_fifo_data[287:272]   ,
                s_p_ack_gather_fifo_data[271:256]   ,
                s_p_ack_gather_fifo_data[255:0]
                );
        end
end

///
wire                                s_p_axi_st_tx_rdy               ;
wire                                s_p_axi_st_tx_vld               ;
wire        [255:0]                 s_p_axi_st_tx_tdata             ;
wire        [31:0]                  s_p_axi_st_tx_tkeep             ;
wire        [1:0]                   s_p_axi_st_tx_tuser             ;
wire        [2:0]                   s_p_axi_st_tx_vport             ;


assign s_p_axi_st_tx_rdy            = tb_yuf.u_fd_ack_wrapper.i_send_ack_axi_st_tx_tready;
assign s_p_axi_st_tx_vld            = tb_yuf.u_fd_ack_wrapper.o_send_ack_axi_st_tx_tvalid;
assign s_p_axi_st_tx_tdata[255:0]   = tb_yuf.u_fd_ack_wrapper.o_send_ack_axi_st_tx_tdata[255:0];
assign s_p_axi_st_tx_tuser[1:0]     = tb_yuf.u_fd_ack_wrapper.o_send_ack_axi_st_tx_tuser[1:0];
assign s_p_axi_st_tx_vport[2:0]     = tb_yuf.u_fd_ack_wrapper.o_send_ack_axi_st_tx_vport[2:0];


/// sqe data
integer sim_fd_ack_wrapper_out_meta;
initial
begin
    sim_fd_ack_wrapper_out_meta = $fopen("../nv_script/data/out/sim_fd_ack_wrapper_out_meta.txt", "w");
end
always @(posedge clk)
begin
    if(s_p_axi_st_tx_rdy && s_p_axi_st_tx_vld)
        begin
            $fdisplay(
                sim_fd_ack_wrapper_out_meta,
                "%h, %h, %h",
                s_p_axi_st_tx_tdata[255:0]  ,
                s_p_axi_st_tx_tuser[1:0]    ,
                s_p_axi_st_tx_vport[2:0]
                );
        end
end

///
wire                                s_p_acktaildb_update_rdy                ;
wire                                s_p_acktaildb_update_vld                ;
wire        [32:0]                  s_p_acktaildb_update_data               ;


assign s_p_acktaildb_update_rdy         = tb_yuf.u_fd_ack_wrapper.i_acktaildb_update_rdy;
assign s_p_acktaildb_update_vld         = tb_yuf.u_fd_ack_wrapper.o_acktaildb_update_vld;
assign s_p_acktaildb_update_data[32:0]  = tb_yuf.u_fd_ack_wrapper.o_acktaildb_update_data[32:0];


/// sqe data
integer sim_fd_ack_wrapper_acktaildb_update_meta;
initial
begin
    sim_fd_ack_wrapper_acktaildb_update_meta = $fopen("../nv_script/data/out/sim_fd_ack_wrapper_acktaildb_update_meta.txt", "w");
end
always @(posedge clk)
begin
    if(s_p_acktaildb_update_rdy && s_p_acktaildb_update_vld)
        begin
            $fdisplay(
                sim_fd_ack_wrapper_acktaildb_update_meta,
                "%h",
                s_p_acktaildb_update_data[32:0]
                );
        end
end