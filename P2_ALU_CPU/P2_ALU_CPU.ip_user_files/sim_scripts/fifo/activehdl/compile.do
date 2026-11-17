transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib activehdl/fifo_generator_v13_2_15
vlib activehdl/xil_defaultlib

vmap fifo_generator_v13_2_15 activehdl/fifo_generator_v13_2_15
vmap xil_defaultlib activehdl/xil_defaultlib

vlog -work fifo_generator_v13_2_15  -v2k5 "+incdir+G:/2026.1/Vivado/data/rsb/busdef" -l fifo_generator_v13_2_15 -l xil_defaultlib \
"../../../ipstatic/simulation/fifo_generator_vlog_beh.v" \

vcom -work fifo_generator_v13_2_15 -93  \
"../../../ipstatic/hdl/fifo_generator_v13_2_vh_sim_rfs.vhd" \

vlog -work fifo_generator_v13_2_15  -v2k5 "+incdir+G:/2026.1/Vivado/data/rsb/busdef" -l fifo_generator_v13_2_15 -l xil_defaultlib \
"../../../ipstatic/hdl/fifo_generator_v13_2_vl_sim_rfs.v" \

vlog -work xil_defaultlib  -v2k5 "+incdir+G:/2026.1/Vivado/data/rsb/busdef" -l fifo_generator_v13_2_15 -l xil_defaultlib \
"../../../../../P1_RS232/P1_RS232.gen/sources_1/ip/fifo/sim/fifo.v" \


vlog -work xil_defaultlib \
"glbl.v"

