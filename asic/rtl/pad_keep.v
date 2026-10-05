// Synthesis-only black boxes, passed via EXTRA_VERILOG_MODELS. They replace
// the Liberty black boxes of the same cells and carry (* keep *): GHDL drops
// VHDL keep attributes, and without it Yosys removes the port-less power
// pads and the spare input pads (unused p2c) from the netlist.
(* keep *) module sg13cmos5l_IOPadVdd (); endmodule
(* keep *) module sg13cmos5l_IOPadVss (); endmodule
(* keep *) module sg13cmos5l_IOPadIOVdd (); endmodule
(* keep *) module sg13cmos5l_IOPadIOVss (); endmodule
(* keep *) module sg13cmos5l_IOPadIn (inout pad, output p2c); endmodule
