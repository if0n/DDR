module load spyglass/P-2019.06-SP2
bsub -Is spyglass

source spyglass_fdma.tcl
# exit close_project -force
close_project -force
source spyglass_fdma.tcl



# bsub -Is verdi -ssf tb_yuf.fsdb