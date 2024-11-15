################################################################################
+incdir+../0_SIM/common
+incdir+../0_SRC/common
+incdir+../0_SRC/include

../0_SIM/common/glbl.v
../0_SIM/common/sv_assert.sv

../0_SRC/common/cm_hyper_pipe.v
../0_SRC/common/cm_ram_simple_dual_one_clock.v
../0_SRC/common/cm_vr_sfifo_ctrl.v
../0_SRC/common/cm_vr_sfifo_ctrl_wrapper.v

../0_SRC/include/ddr_define.vh

../0_SRC/memory_wrap/xfpga_wrapper/xfpga_sdpram_wrapper.v

#tb path
../0_SIM/tb_ddr_v1/axi_self_test_master.v
../0_SIM/tb_ddr_v1/micron_ddr_sdram_model.v
../0_SIM/tb_ddr_v1/tb_ddr_sdram_ctrl.v

../0_SRC/rtl_ddr_v1/ddr_sdram_ctrl.v
../0_SRC/rtl_ddr_v1/sdpram_wrapper.v
../0_SRC/rtl_ddr_v1/sfifo_wrapper.v

