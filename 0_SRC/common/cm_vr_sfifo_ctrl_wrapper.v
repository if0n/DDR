module cm_vr_sfifo_ctrl_wrapper
#(
    parameter WIDTH_DATA        = 32   ,
	parameter WIDTH_ADDR        = 4    ,
	parameter WATERRAGE_UP       = 5    ,
	parameter WATERRAGE_DOWN     = 1    ,
	parameter SHOW_AHEAD        = 0
)
(
    input  wire                        clk         ,
    input  wire                        rst_n       ,
    input  wire                        clr         ,

    input  wire                        wr_en       ,
    input  wire [WIDTH_DATA - 1:0]     wr_data     ,
	output wire                        full        ,

    input  wire                        rd_en       ,
    output wire [WIDTH_DATA - 1:0]     rd_dout     ,
    output wire                        empty       ,

    output wire                        alfull      ,
    output wire                        alempty     ,

    output wire                        ram_wen     ,
    output wire [ WIDTH_DATA-1:0]      ram_wdata   ,
    output wire [ WIDTH_ADDR-1:0]      ram_waddr   ,
    output wire                        ram_ren     ,
    output wire [ WIDTH_ADDR-1:0]      ram_raddr   ,
    input  wire [ WIDTH_DATA-1:0]      ram_rdata
);
    wire                       wr_valid       ;
    wire                       wr_ready       ;
    wire                       rd_valid       ;
    wire                       rd_ready       ;

    assign full        = ~wr_ready;
    assign empty       = ~rd_valid && ~full;
    assign wr_valid    = wr_en    ;
    assign rd_ready    = rd_en    ;

generate
    if((WATERRAGE_UP != 0) || (WATERRAGE_DOWN != 0)) begin:WATERRAGE
        reg  [WIDTH_ADDR:0] ram_use             ;
        reg                 ram_alfull          ;
        reg                 ram_alempty         ;

	    assign alfull  = ram_alfull;
        assign alempty = ram_alempty;

        always @(posedge clk or negedge rst_n) begin
            if(~rst_n) begin
                ram_use     <= {(WIDTH_ADDR+1){1'b0}};
                ram_alfull  <= 1'b0;
                ram_alempty <= 1'b1;
            end
            else if(clr) begin
                ram_use     <= {(WIDTH_ADDR+1){1'b0}};
                ram_alfull  <= 1'b0;
                ram_alempty <= 1'b1;
            end
            else begin
                case({rd_valid & rd_ready,wr_valid & wr_ready})
                2'b10: begin
                    ram_use     <= (|ram_use) ? ram_use - 1'b1 : {(WIDTH_ADDR+1){1'b0}};
                    ram_alfull  <= ram_use > (2**WIDTH_ADDR - WATERRAGE_UP);
                    ram_alempty <= ram_use <= WATERRAGE_DOWN;
                end
                2'b01: begin
                    ram_use     <= ram_use[WIDTH_ADDR] ? {1'b1,{WIDTH_ADDR{1'b0}}} : ram_use + 1'b1;
                    ram_alfull  <= ram_use >= (2**WIDTH_ADDR - WATERRAGE_UP - 1);
                    ram_alempty <= ram_use < (WATERRAGE_DOWN - 1);
                end
                default: begin
                    ram_use     <= ram_use;
                    ram_alfull  <= ram_alfull;
                    ram_alempty <= ram_alempty;
                end
                endcase
            end
        end
    end
    else begin:NOWATERRAGE
        assign alfull   = 1'b0;
        assign alempty  = 1'b0;
    end
endgenerate


generate
    if(SHOW_AHEAD) begin:SHOWAHEAD
		cm_vr_sfifo_ctrl
		#(
		    .WIDTH      ( WIDTH_DATA    ),
		    .DEEP_SIZE  ( WIDTH_ADDR    )
		)u_cm_vr_sfifo_ctrl
			(
			.clk        (clk            ),
			.rst_n      (rst_n          ),
			.clr        (clr            ),

			.ups_data   (wr_data        ),//i
			.ups_valid  (wr_valid       ),//i
			.ups_ready  (wr_ready       ),//o
			.dns_data   (rd_dout        ),//o
			.dns_valid  (rd_valid       ),//o
			.dns_ready  (rd_ready       ),//i

			.wen        (ram_wen        ),
			.wdata      (ram_wdata      ),
			.waddr      (ram_waddr      ),
			.ren        (ram_ren        ),
			.raddr      (ram_raddr      ),
			.rdata      (ram_rdata      )
		);
	end
	else begin:NORMAL
    reg  [WIDTH_DATA - 1:0]   dns_data_d ;
    wire [WIDTH_DATA - 1:0]   rd_data    ;
		assign rd_dout = dns_data_d;

		always @(posedge clk or negedge rst_n) begin
			if(~rst_n) begin
				dns_data_d  <= {WIDTH_DATA{1'b0}};
			end
			else if(clr) begin
				dns_data_d  <= {WIDTH_DATA{1'b0}};
			end
			else if(rd_valid && rd_ready) begin
				dns_data_d  <= rd_data;
			end
		end

		hqos_vr_sfifo_ctrl
		#(
			.WIDTH      ( WIDTH_DATA    ),
			.DEEP_SIZE  ( WIDTH_ADDR    )
		)u_hqos_vr_sfifo_ctrl
		(
			.clk        (clk            ),
			.rst_n      (rst_n          ),
			.clr        (clr            ),

			.ups_data   (wr_data        ),//i
			.ups_valid  (wr_valid       ),//i
			.ups_ready  (wr_ready       ),//o
			.dns_data   (rd_data        ),//o
			.dns_valid  (rd_valid       ),//o
			.dns_ready  (rd_ready       ),//i

			.wen        (ram_wen        ),
			.wdata      (ram_wdata      ),
			.waddr      (ram_waddr      ),
			.ren        (ram_ren        ),
			.raddr      (ram_raddr      ),
			.rdata      (ram_rdata      )
		);
	end
endgenerate



endmodule

