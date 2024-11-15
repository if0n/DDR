`define sv_assert(signal, value) \
    assert (signal === value) else begin \
        $display("ASSERTION FAILED in %m: ##signal != ##value"); \
        $display("signal = %x value = %x", signal, value); \
        #100; $finish; \
    end
