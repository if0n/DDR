################################################################################
+incdir+../nv_sim/common
+incdir+../nv_sim/tb_fbc
+incdir+../nv_src/common
+incdir+../nv_src/include

../nv_src/include/nvme_define.vh

#tb path
../nv_sim/tb_fbc/glbl.v

../nv_sim/tb_fbc/tb_yuf.v
../nv_sim/tb_fbc/sim_service_hqos_fbc.v


../nv_src/hqos_common/hqos_ram_simple_dual_one_clock.v
../nv_src/hqos_common/hqos_vr_sfifo_ctrl.v
../nv_src/hqos_common/hqos_vr_sfifo_ctrl_wrapper.v

../nv_src/hqos_flow_ctrl/common/hqos_hyper_pipe.v

../nv_src/hqos_flow_ctrl/qos_flow_bucket_ctrl/hqos_fb_alg_pass_judge.v
../nv_src/hqos_flow_ctrl/qos_flow_bucket_ctrl/hqos_flow_bucket_ctrl.v
../nv_src/hqos_flow_ctrl/qos_flow_bucket_ctrl/hqos_sdpram_wrapper.v
../nv_src/hqos_flow_ctrl/qos_flow_bucket_ctrl/hqos_sfifo_wrapper.v

#nvme mem