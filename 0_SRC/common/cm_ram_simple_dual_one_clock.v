module cm_ram_simple_dual_one_clock #(
    parameter       WIDTH   =   256 ,
    parameter       SIZE    =   10
    )
    (
    input   wire                        clk         ,
    input   wire                        ena         ,
    input   wire                        enb         ,
    input   wire                        wea         ,
    input   wire    [SIZE -  1:0]       addra       ,
    input   wire    [SIZE -  1:0]       addrb       ,
    input   wire    [WIDTH - 1:0]       dia         ,
    output  reg     [WIDTH - 1:0]       dob
    );

(*ram_style = "block"*) reg [WIDTH - 1:0] ram [2**SIZE - 1:0];

always @(posedge clk)  //
    begin
        if (ena)
            begin
                if (wea)
                    begin
                        ram[addra] <= dia;
                    end
            end
    end

always @(posedge clk)  //changed by yangf
    begin
        if (enb)
            begin
                dob <= ram[addrb] ;
            end
    end


endmodule
