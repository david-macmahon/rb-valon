#!/usr/bin/env ruby

# Just dump the register contents in hex and binary.

require 'valon'

class Valon::Synth
  def dump_regs(synth)
    errs = 0
    regs = read_registers(synth)
    regs.each_with_index do |r, i|
      printf "%d: %08x %032b", i, r, r
      print " BAD" if (r&7) != i
      puts
    end
  end
end

vs = Valon::Synth.new(ARGV[0]||'/dev/ttyUSB0')
label = vs.label
label = 'Unlabled Valon' if label.empty?
vco_min, vco_max = vs.vco_range

puts <<EOF
Setings for #{label}

Reference: #{vs.is_ext_ref? ? 'External' : 'Internal'}
Ref Freq : #{vs.ref_freq / 1e6} MHz
VCO Range: #{vco_min} MHz to #{vco_max} MHz

Synth A: PFD freq #{vs.freq_a_pfd/1e6} MHz
Synth A: VCO freq #{vs.freq_a_vco/1e6} MHz
Synth A: RF  freq #{vs.freq_a_rf/1e6} MHz
Synth A: RF power #{'%+d' % vs.a_dbm} dBm
Synth A: Locked : #{vs.is_a_locked? ? 'yes' : 'NO'}

Synth B: PFD freq #{vs.freq_b_pfd/1e6} MHz
Synth B: VCO freq #{vs.freq_b_vco/1e6} MHz
Synth B: RF  freq #{vs.freq_b_rf/1e6} MHz
Synth B: RF power #{'%+d' % vs.b_dbm} dBm
Synth B: Locked : #{vs.is_b_locked? ? 'yes' : 'NO'}
EOF

puts
puts 'Synth A registers:'
vs.dump_regs(Valon::Synth::SYNTH_A)

puts
puts 'Synth B registers:'
vs.dump_regs(Valon::Synth::SYNTH_B)

widths = Valon::Synth::FIELD_INFO.keys.map {|k| k.length}
width = widths.max

puts
printf "%-*s      A      B\n", width, 'Field'
printf "%-*s==============\n", width, '='*width
Valon::Synth::FIELD_INFO.keys.each do |f|
  printf "%-*s  %5d  %5d\n", width, f,
    vs.send("a_#{f}"), vs.send("b_#{f}")
end
