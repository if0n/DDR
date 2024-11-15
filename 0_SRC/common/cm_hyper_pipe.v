// ******************************************************************************
//                                                                              *
//                  Copyright (C) 2015 Altera Corporation                       *
//                                                                              *
// ALTERA, ARRIA, CYCLONE, HARDCOPY, MAX, MEGACORE, NIOS, QUARTUS & STRATIX     *
// are Reg. U.S. Pat. & Tm. Off. and Altera marks in and outside the U.S.       *
//                                                                              *
// All information provided herein is provided on an "as is" basis,             *
// without warranty of any kind.                                                *
//                                                                              *
// Module Name: hyper_pipe                   File Name: hyper_pipe.s            *
//                                                                              *
// Module Function: This file implements a parameterizable bus of pipeline      *
//     registers for Altera training class                                      *
//                                                                              *
// REVISION HISTORY:                                                            *
//     1.0    00/00/0000 - Initial Revision  for QII 14.0                       * 
// ******************************************************************************
`timescale 1ns / 1ps

module cm_hyper_pipe #(
    parameter WIDTH         =   1   ,
    parameter NUM_PIPES     =   1
    )
    (
    input   wire                    clk     ,
    input   wire                    rst_n   ,
    input   wire    [WIDTH-1:0]     din     ,
    output  wire    [WIDTH-1:0]     dout
    );

///*********************************************************************
///main function
///*********************************************************************
generate
    if (NUM_PIPES == 0)
        begin
            assign dout = din;
        end
    else
        begin
            genvar i;
            reg     [WIDTH-1:0]     hp  [NUM_PIPES-1:0] ;

            always @(posedge clk or negedge rst_n)
            begin
                if(!rst_n)
                    hp[0]   <= {WIDTH{1'b0}};
                else
                    hp[0]   <= din;
            end

            for (i=1; i<NUM_PIPES; i=i+1)
                begin: hregs
                    always @(posedge clk or negedge rst_n)
                    begin
                        if(!rst_n)
                            hp[i]   <= {WIDTH{1'b0}};
                        else
                            hp[i]   <= hp[i-1];
                    end
                end

            assign dout = hp[NUM_PIPES-1];
        end
endgenerate

endmodule
