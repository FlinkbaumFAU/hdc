# frozen_string_literal: true

# Hard-IP handling for the full-chip LVS of hdc_chip_top, called from
# sg13cmos5l_chip.lvs right after `align`, in place of the deck's own
# simplification of both netlists.
#
# The PDK netlists of the IO cells and SRAM macros don't match their own
# layouts in the cmos5l deck (IO diodes/clamps, the SRAM delay dummy
# RSC_IHPSG13_CDLYX1_DUMMY), so these cells are compared as black boxes:
# only their pins and what the chip connects to them are checked.
#
# - IO fillers / corner: rails plus substrate taps, no schematic instances.
#   Their taps are dropped and the cells flattened, so the rails still join
#   the pads at the top level.
# - Layout: simplified first (as the deck does), then pads and SRAMs blanked.
#   Simplifying after blanking would keep dozens of unnamed rail-fragment pins.
# - Schematic: blanked first, then simplified, so the pads keep all pins
#   (simplify would drop power pins that are floating inside the CDL cell).
# - Pad pins are then reconciled by name. Layout pins without a name
#   (substrate) or without a schematic counterpart are removed; duplicate
#   layout pins of one name are merged only if every instance already
#   connects them to the same net (otherwise this raises, nothing is faked).
#   Schematic pins the layout cell doesn't have (rails without devices in
#   that pad, e.g. iovdd in IOPadVdd) are removed as well.

HARD_IP_PADS = /\Asg13cmos5l_IOPad/i
HARD_IP_SRAM = /\ARM_IHPSG13_1P_/i
HARD_IP_RAILS = /\Asg13cmos5l_(Filler|Corner)/i

def hard_ip_prune(nl, top_name)
  loop do
    dead = []
    nl.each_circuit do |c|
      next if c.name.casecmp?(top_name)

      refs = 0
      c.each_ref { |_r| refs += 1 }
      dead << c if refs.zero?
    end
    break if dead.empty?

    dead.each { |c| nl.remove_circuit(c) }
  end
end

def hard_ip_blank(nl)
  list = []
  nl.each_circuit { |c| list << c if c.name =~ HARD_IP_PADS || c.name =~ HARD_IP_SRAM }
  list.each(&:blank)
end

def hard_ip_find(nl, name)
  found = nil
  nl.each_circuit { |c| found = c if c.name.casecmp?(name) }
  found
end

def hard_ip_remove_pin(circuit, pin)
  refs = []
  circuit.each_ref { |sc| refs << sc }
  refs.each { |sc| sc.disconnect_pin(pin.id) }
  circuit.remove_pin(pin.id)
end

def apply_hard_ip(layout_nl, schematic_nl, top_name, logger)
  logger.info('Hard IP: flattening IO fillers/corner without their taps')
  rails = []
  layout_nl.each_circuit { |c| rails << c if c.name =~ HARD_IP_RAILS }
  rails.each do |c|
    devs = []
    c.each_device { |d| devs << d }
    devs.each { |d| c.remove_device(d) }
    layout_nl.flatten_circuit(c)
  end

  # Inside the pads anyway; Netlist#simplify trips over its rppd devices
  # ("Terminal still connected after removing device").
  layout_nl.each_circuit { |c| c.blank if c.name =~ /\Asg13cmos5l_RCClampResistor\z/i }

  logger.info('Hard IP: layout simplify, then blank pads and SRAM macros')
  layout_nl.simplify
  hard_ip_blank(layout_nl)
  hard_ip_prune(layout_nl, top_name)

  logger.info('Hard IP: schematic blank pads and SRAM macros, then simplify')
  hard_ip_blank(schematic_nl)
  hard_ip_prune(schematic_nl, top_name)
  schematic_nl.simplify

  layout_nl.each_circuit do |c|
    next unless c.name =~ HARD_IP_PADS

    sch = hard_ip_find(schematic_nl, c.name)
    raise "Hard IP: no schematic counterpart for #{c.name}" unless sch

    sch_names = []
    sch.each_pin { |p| sch_names << p.name.upcase }
    by_name = Hash.new { |h, k| h[k] = [] }
    c.each_pin { |p| by_name[p.name.upcase] << p }

    by_name.each do |name, pins|
      if name.empty? || !sch_names.include?(name)
        pins.each { |p| hard_ip_remove_pin(c, p) }
        next
      end
      keep = pins.first
      pins.drop(1).each do |p|
        c.each_ref do |sc|
          a = sc.net_for_pin(keep.id)
          b = sc.net_for_pin(p.id)
          next if a && b && a.expanded_name == b.expanded_name

          raise "Hard IP: #{sc.expanded_name} (#{c.name}) pin #{name} is split: " \
                "#{a&.expanded_name.inspect} vs #{b&.expanded_name.inspect}"
        end
        hard_ip_remove_pin(c, p)
      end
    end

    lay_names = []
    c.each_pin { |p| lay_names << p.name.upcase }
    extra = []
    sch.each_pin { |p| extra << p unless lay_names.include?(p.name.upcase) }
    extra.each do |p|
      logger.info("Hard IP: #{sch.name} pin #{p.name} has no layout counterpart, removed")
      hard_ip_remove_pin(sch, p)
    end
  end
end
