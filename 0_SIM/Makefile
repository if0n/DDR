#-----------------------------------------------------------------
# options comments:
#-----------------------------------------------------------------
#	lint: 	'+lint=all' or '+lint=IRIMW +lint=GCWM +lint=TFIPC +lint=IPDP +lint==PCWM'
# 			Lint-[IRIMW] Illegal range in memory word
# 			Lint-[NCEID} Non-constant expression in delay
# 			Lint-[GCWM] Gate connection width mismatch
# 			Lint-[CAWM] Continuous Assignment width mismatch
# 			Lint-[IGSFPG] Illegal gate strength for pull gate
# 			Lint-[TFIPC] Too few instance port connections
# 			Lint-[IPDP] Identifier previously declared as port
# 			Lint-[PCWM] Port connect width mismatch
# 			Lint-[VCDE] Verilog compiler directive encountered
#-----------------------------------------------------------------
#	dve:	dve -covdir *.vdb &
# 			urg -dir simv.vdb -report urgReport
# 			firefox urgReport/dashboard.html
#-----------------------------------------------------------------

F_ARGS				?= -f sim_g.f
F_ARGS_VHDL			?= -f sim_g_vhdl.f
TOP					?= tb_ddr_sdram_ctrl
PLI					?= /App/synopsys/verdi/R-2020.12/share/PLI/VCS/LINUX64/novas.tab /App/synopsys/verdi/R-2020.12/share/PLI/VCS/LINUX64/pli.a
TS					?= -timescale=1ns/1ps

# VCS_OPT0			?= +vcs+initreg+random
# VCS_OPT1			?= -cm line+cond+fsm+tgl+branch +lint=all -cm_nocasedef -xzcheck +vcs+flush+all
# SIM_OPT0			?= +vcs+initreg+0	+vcs+initmem+0
# SIM_OPT1			?= -cm line+cond+fsm+tgl+branch +lint=all -cm_nocasedef
VCS_OPT0			?= +vcs+initreg+random
VCS_OPT1			?=
SIM_OPT0			?= +vcs+initreg+0	+vcs+initmem+0
SIM_OPT1			?=
LINT_OPT			?= +lint=IRIMW +lint=GCWM +lint=CAWM +lint=IPDP +lint=TFIPC-L +lint==PCWM-L +lint=TPIPC-L

all : analy compl simul

clean :
#	rm -rf *.fsdb simv simv.daidir simv.vdb urgReport DVEfiles csrc ucli.key *log novas.conf novas.rc verdiLog vcs_lib verdi_config_file
	rm -rf *.fsdb vcs_lib

#Step 1: analysis verilog/system verilog/VHDL .c
analy :
	bsub -Is vlogan \
		-full64 -sverilog +v2k	-debug_access+all -kdb -lca $(TS) +error+50 -q -j64 -assert svaext \
		+no_notifier -debug_region+cell+encrypt \
		$(LINT_OPT) \
    	-work xil_defaultlib $(F_ARGS) -l vlg.log

analy_vhdl :
	bsub -Is vhdlan \
		-full64 \
    	-work xil_defaultlib $(F_ARGS_VHDL) -l vlg_vhdl.log

#Step 2: Elaboration/Compilation .o
compl :
	bsub -Is vcs \
		-full64 -sverilog 		-debug_access+all -kdb -lca $(TS) +error+50 -q -j64 \
		+no_notifier -debug_region+cell+encrypt \
		+notimingcheck+nospecify+delay_mode_zero+overlap \
		-Mupdate -licqueue -t ps \
		$(LINT_OPT) \
		$(VCS_OPT0) \
		$(VCS_OPT1) \
		-P $(PLI) -top $(TOP) -top glbl -l elba.log

#Step 3: Run simulation .e
simul :
	bsub -Is ./simv \
		-ucli -licqueue -j64\
		$(LINT_OPT) \
		$(SIM_OPT0) \
		$(SIM_OPT1) \
		-do simulate.do -l simulate.log

verdi :
	bsub -Is verdi \
		-gui $(F_ARGS) $(F_ARGS_VHDL) -ssf ${TOP}.fsdb -sv -2012 -swwr signal_0914.rc

cov :
	dve -covdir *.vdb &

urg :
	urg -dir simv.vdb -report urgReport

dashboard :
	firefox urgReport/dashboard.html
