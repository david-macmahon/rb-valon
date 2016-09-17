#!/usr/bin/env ruby

# Just dump the register contents in hex and binary.

require 'valon'

class Valon::Synth
  def dump_regs(synth)
    errs = 0
    status = read_ctrl_status
    regs = read_registers(synth)
    regs.each_with_index do |r, i|
      printf "%d: %08x %032b", i, r, r
      print " BAD" if (r&7) != i
      puts
    end
  end
end

vs = Valon::Synth.new(ARGV[0]||'/dev/ttyUSB0')

print 'Synth A ('
print 'NOT ' unless vs.is_locked?(Valon::Synth::SYNTH_A)
puts 'locked)'
vs.dump_regs(Valon::Synth::SYNTH_A)

puts
print 'Synth B ('
print 'NOT ' unless vs.is_locked?(Valon::Synth::SYNTH_B)
puts 'locked)'
vs.dump_regs(Valon::Synth::SYNTH_B)

widths = Valon::Synth::FIELD_INFO.keys.map {|k| k.length}
width = widths.max

puts
Valon::Synth::FIELD_INFO.keys.each do |f|
  printf "%-*s  %5d  %5d\n", width, f,
    vs.send("a_#{f}"), vs.send("b_#{f}")
end
