module cm_vr_sfifo_ctrl
#(
    parameter WIDTH     = 290,
    parameter DEEP_SIZE = 7
)
(
    input  wire                 clk             ,
    input  wire                 rst_n           ,
    input  wire                 clr             ,
    input  wire [ WIDTH-1:0]    ups_data        ,
    input  wire                 ups_valid       ,
    output reg                  ups_ready       ,
    output wire [ WIDTH-1:0]    dns_data        ,
    output reg                  dns_valid       ,
    input  wire                 dns_ready       ,

    output wire                 wen             ,
    output wire [ WIDTH-1:0]    wdata           ,
    output wire [DEEP_SIZE-1:0] waddr           ,
    output wire                 ren             ,
    output wire [DEEP_SIZE-1:0] raddr           ,
    input  wire [ WIDTH-1:0]    rdata
);

/************ ************ ************/
reg  [DEEP_SIZE - 1:0]      head            ;
reg  [DEEP_SIZE - 1:0]      tail            ;
wire [DEEP_SIZE - 1:0]      tail_nxt        ;

always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            begin
                head    <= {DEEP_SIZE{1'b0}};
                tail    <= {DEEP_SIZE{1'b0}};
            end
        else if(clr)
            begin
                head    <= {DEEP_SIZE{1'b0}};
                tail    <= {DEEP_SIZE{1'b0}};
            end
        else
            begin
                if(ups_valid & ups_ready)
                    begin
                        tail    <= tail + 1'b1;
                    end
                if(ren)
                    begin
                        head    <= head + 1'b1;
                    end
            end
    end

assign wen      = ups_valid & ups_ready;
assign wdata    = ups_data;
assign waddr    = tail;

assign ren      = (ups_ready ^ (head == tail)) & ((~dns_valid) | (dns_valid & dns_ready));
assign raddr    = head;
assign dns_data = rdata;

always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            begin
                dns_valid   <= 1'b0;
            end
        else if(clr)
            begin
                dns_valid   <= 1'b0;
            end
        else if(ren)
            begin
                dns_valid   <= 1'b1;
            end
        else if(dns_valid & dns_ready)
            begin
                dns_valid   <= 1'b0;
            end
    end

assign tail_nxt = tail + 1'b1;

always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            begin
                ups_ready   <= 1'b1;
            end
        else if(clr)
            begin
                ups_ready   <= 1'b1;
            end
        else
            begin
                case({wen,ren})
                    2'b01:
                        begin
                            ups_ready   <= 1'b1;
                        end
                    2'b10:
                        begin
                            ups_ready   <= (tail_nxt == head) ? 1'b0 : 1'b1;
                        end
                    default:
                        begin
                            ups_ready   <= ups_ready;
                        end
                endcase
            end
    end

endmodule

