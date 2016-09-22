#!/usr/bin/env ruby

# Just dump the register contents in hex and binary.

require 'valon'

def dump_regs(regs)
  regs.each_with_index do |r, i|
    printf "%d: %08x %032b", i, r, r
    print " BAD" if (r&7) != i
    puts
  end
end

vs = Valon::Synth.new(ARGV[0]||'/dev/ttyUSB0')
label = vs.label
label = 'Unlabled Valon' if label.empty?
vco_min, vco_max = vs.vco_range

freq_a_rf  = '%12.6f' % (vs.freq_a_rf  / 1e6)
freq_a_vco = '%12.6f' % (vs.freq_a_vco / 1e6)
freq_a_pfd = '%12.6f' % (vs.freq_a_pfd / 1e6)
a_n  = '%5d' % vs.a_int
a_n += ' %d/%d' % [vs.a_frac, vs.a_mod] if vs.a_frac != 0

freq_b_rf  = '%12.6f' % (vs.freq_b_rf  / 1e6)
freq_b_vco = '%12.6f' % (vs.freq_b_vco / 1e6)
freq_b_pfd = '%12.6f' % (vs.freq_b_pfd / 1e6)
b_n  = '%5d' % vs.b_int
b_n += ' %d/%d' % [vs.b_frac, vs.b_mod] if vs.b_frac != 0

puts <<EOF
Setings for #{label}

Reference: #{vs.is_ext_ref? ? 'External' : 'Internal'}
Ref Freq : #{vs.ref_freq / 1e6} MHz
VCO Range: #{vco_min} MHz to #{vco_max} MHz

Synth A: OUT freq #{freq_a_rf} MHz
Synth A: VCO freq #{freq_a_vco} MHz
Synth A: N divide #{a_n}
Synth A: PFD freq #{freq_a_pfd} MHz
Synth A: RF power    #{'%+d' % vs.a_dbm} dBm
Synth A: Lock #{vs.is_a_locked? ? ' OK' : 'BAD'}

Synth B: OUT freq #{freq_b_rf} MHz
Synth B: VCO freq #{freq_b_vco} MHz
Synth B: N divide #{b_n}
Synth B: PFD freq #{freq_b_pfd} MHz
Synth B: RF power    #{'%+d' % vs.b_dbm} dBm
Synth B: Lock #{vs.is_b_locked? ? ' OK' : 'BAD'}
EOF

puts
puts 'Synth A registers:'
dump_regs(vs.registers[0])

puts
puts 'Synth B registers:'
dump_regs(vs.registers[1])

widths = Valon::Synth::FIELD_INFO.keys.map {|k| k.length}
width = widths.max

puts
printf "%-*s      A      B\n", width, 'Field'
printf "%-*s==============\n", width, '='*width
Valon::Synth::FIELD_INFO.keys.each do |f|
  printf "%-*s  %5d  %5d\n", width, f,
    vs.send("a_#{f}"), vs.send("b_#{f}")
end
