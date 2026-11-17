vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/fifo_generator_v13_2_15
vlib modelsim_lib/msim/xil_defaultlib

vmap fifo_generator_v13_2_15 modelsim_lib/msim/fifo_generator_v13_2_15
vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib

vlog -work fifo_generator_v13_2_15  -incr -mfcu  "+incdir+G:/2026.1/Vivado/data/rsb/busdef" \
"../../../ipstatic/simulation/fifo_generator_vlog_beh.v" \

vcom -work fifo_generator_v13_2_15  -93  \
"../../../ipstatic/hdl/fifo_generator_v13_2_vh_sim_rfs.vhd" \

vlog -work fifo_generator_v13_2_15  -incr -mfcu  "+incdir+G:/2026.1/Vivado/data/rsb/busdef" \
"../../../ipstatic/hdl/fifo_generator_v13_2_vl_sim_rfs.v" \

vlog -work xil_defaultlib  -incr -mfcu  "+incdir+G:/2026.1/Vivado/data/rsb/busdef" \
"../../../../../P1_RS232/P1_RS232.gen/sources_1/ip/fifo/sim/fifo.v" \


vlog -work xil_defaultlib \
"glbl.v"

