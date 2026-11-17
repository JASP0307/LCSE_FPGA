transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+fifo  -L xil_defaultlib -L fifo_generator_v13_2_15 -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.fifo xil_defaultlib.glbl

do {fifo.udo}

run 1000ns

endsim

quit -force
