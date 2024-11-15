module xfpga_spram_wrapper
    #(
        parameter   DEPTH               = 32                               , // depth
        parameter   DW                  = 32                               , // data width
        parameter   AW                  = $clog2(DEPTH)>0? $clog2(DEPTH):1 , // depth 32 -> addr 5?at least 1
        parameter   BYTE_WRITE_WIDTH_A  = DW                               , // BYTE WRITE WIDTH for port-A, if BYTE_WRITE_WIDTH_A is DW, means disable BYTE Write
        parameter   READ_LATENCY_A      = 1                                ,
        parameter   WRITE_MODE_A        = "read_first"                     , // no_change, read_first, write_first. Default value = no_change.
        parameter   MEMORY_TYPE         = "auto"                           , // "auto"  "block"  "distributed"  "ultra"- URAM
        parameter   INIT_FILE           = "none"                             // "none"--> not use init file
    )
(

// write port-A
input  wire                              clk_a    ,  // write clk for port-A
input  wire                              rst_a    ,  // reset for FPGA dout of port-A, active high
input  wire                              en_a     ,  // memory eanble for port-A, active high
input  wire  [DW/BYTE_WRITE_WIDTH_A-1:0] wen_a    ,  // write  enable for port-A, active high
input  wire  [AW  -1 : 0]                addr_a   ,
input  wire  [DW  -1 : 0]                din_a    ,
output wire  [DW  -1 : 0]                dout_a

);


   // xpm_memory_sdpram: Simple Dual Port RAM
   // Xilinx Parameterized Macro, version 2020.2

    xpm_memory_spram #(
        .ADDR_WIDTH_A            ( AW                    ) , // DECIMAL
        .AUTO_SLEEP_TIME         ( 0                     ) , // DECIMAL
        .BYTE_WRITE_WIDTH_A      ( BYTE_WRITE_WIDTH_A    ) , // DECIMAL, if BYTE_WRITE_WIDTH_A = DW, means to enable word-wide writes
        .CASCADE_HEIGHT          ( 0                     ) , // DECIMAL
        .ECC_MODE                ( "no_ecc"              ) , // String
        .MEMORY_INIT_FILE        ( INIT_FILE             ) , // String
        .MEMORY_INIT_PARAM       ( "0"                   ) , // String
        .MEMORY_OPTIMIZATION     ( "true"                ) , // String
        .MEMORY_PRIMITIVE        ( MEMORY_TYPE           ) , // String
        .MEMORY_SIZE             ( DEPTH * DW            ) , // DECIMAL
        .MESSAGE_CONTROL         ( 0                     ) , // DECIMAL
        .READ_DATA_WIDTH_A       ( DW                    ) , // DECIMAL
        .READ_LATENCY_A          ( READ_LATENCY_A        ) , // READ_LATENCY_A  1
        .READ_RESET_VALUE_A      ( "0"                   ) , // String
        .RST_MODE_A              ( "SYNC"                ) , // String
        .SIM_ASSERT_CHK          ( 0                     ) , // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
        .USE_MEM_INIT            ( INIT_FILE=="none"?0:1 ) , // DECIMAL
        .WAKEUP_TIME             ( "disable_sleep"       ) , // String
        .WRITE_DATA_WIDTH_A      ( DW                    ) , // DECIMAL
        .WRITE_MODE_A            ( WRITE_MODE_A          )   // using read_first, it will read the previous data; but without conflict;
                                                             //       Allowed values: no_change, read_first, write_first. Default value = no_change.
    )
    xpm_memory_spram_inst (
        .dbiterra(),                    // 1-bit output: Status signal to indicate double bit error occurrence
                                        // on the data output of port A.

        .douta(dout_a),                 // READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
        .sbiterra(),                    // 1-bit output: Status signal to indicate single bit error occurrence
                                        // on the data output of port A.

        .addra(addr_a),                 // ADDR_WIDTH_A-bit input: Address for port A write and read operations.
        .clka(clk_a),                   // 1-bit input: Clock signal for port A.

        .dina(din_a),                   // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
        .ena(en_a),                     // 1-bit input: Memory enable signal for port A. Must be high on clock
                                        // cycles when write operations are initiated. Pipelined internally.

        .injectdbiterra(),              // 1-bit input: Controls double bit error injection on input data when
                                        // ECC enabled (Error injection capability is not available in
                                        // "decode_only" mode).

        .injectsbiterra(),              // 1-bit input: Controls single bit error injection on input data when
                                        // ECC enabled (Error injection capability is not available in
                                        // "decode_only" mode).

        .regcea(1'b1),                  // 1-bit input: Clock Enable for the last register stage on the output
                                        // data path.

        .rsta(rst_a),                   // 1-bit input: Reset signal for the final port A output register stage.
                                        // Synchronously resets output port douta to the value specified by
                                        // parameter READ_RESET_VALUE_A.

        .sleep(1'b0),                   // 1-bit input: sleep signal to enable the dynamic power saving feature.
        .wea(wen_a)                     // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
                                        // for port A input data port dina. 1 bit wide when word-wide writes are
                                        // used. In byte-wide write configurations, each bit controls the
                                        // writing one byte of dina to address addra. For example, to
                                        // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
                                        // is 32, wea would be 4'b0010.
    );


endmodule


//////////////////////////////////////



//    // End of xpm_memory_spram_inst instantiation
