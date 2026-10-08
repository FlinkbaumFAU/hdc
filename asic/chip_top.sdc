# Adapted from https://github.com/IHP-GmbH/ihp-sg13-librelane-template (librelane/chip_top.sdc)
current_design $::env(DESIGN_NAME)
set_units -time ns

# Three clocks: the core clock (CLOCK_PERIOD) and the SPI front end, which
# clocks flops on both sclk edges and on the falling edge of cs_n (also its
# async reset). All are defined on the IOPadIn p2c pins. The SPI side reaches
# the core only through toggle synchronizers, so clk is asynchronous to it.
set spi_period 100.0 ;# 10 MHz SCLK; sclk/cs_n are timed against each other

create_clock [get_pins clk_pad/p2c]  -name clk  -period $::env(CLOCK_PERIOD)
create_clock [get_pins sclk_pad/p2c] -name sclk -period $spi_period
create_clock [get_pins cs_n_pad/p2c] -name cs_n -period $spi_period
set_clock_groups -asynchronous -group [get_clocks clk] -group [get_clocks {sclk cs_n}]

set input_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
set output_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
puts "\[INFO] Setting output delay to: $output_delay_value"
puts "\[INFO] Setting input delay to: $input_delay_value"

set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
if { [info exists ::env(MAX_TRANSITION_CONSTRAINT)] } {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
}
if { [info exists ::env(MAX_CAPACITANCE_CONSTRAINT)] } {
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
}

set clocks [get_clocks clk]
set spi_io_delay [expr $spi_period * $::env(IO_DELAY_CONSTRAINT) / 100]

# rstn is asynchronous to clk; constrained like the template's inputs so the
# pad-to-core path is still timed
set_input_delay -min 0 -clock $clocks [get_ports pad_rstn]
set_input_delay -max $input_delay_value -clock $clocks [get_ports pad_rstn]
set_output_delay $output_delay_value -clock $clocks [get_ports pad_led]

# SPI mode 0: mosi sampled on rising sclk, miso shifted on falling sclk
set_input_delay -min 0 -clock [get_clocks sclk] [get_ports pad_mosi]
set_input_delay -max $spi_io_delay -clock [get_clocks sclk] [get_ports pad_mosi]
set_output_delay $spi_io_delay -clock [get_clocks sclk] [get_ports pad_miso]

set cap_load [expr $::env(OUTPUT_CAP_LOAD) / 1000.0]
puts "\[INFO] Setting load to: $cap_load"
set_load $cap_load [all_outputs]

puts "\[INFO] Setting clock uncertainty to: $::env(CLOCK_UNCERTAINTY_CONSTRAINT)"
set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) [all_clocks]

puts "\[INFO] Setting clock transition to: $::env(CLOCK_TRANSITION_CONSTRAINT)"
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) [all_clocks]

puts "\[INFO] Setting timing derate to: $::env(TIME_DERATING_CONSTRAINT)%"
set_timing_derate -early [expr 1-[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]
set_timing_derate -late [expr 1+[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]

if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}

