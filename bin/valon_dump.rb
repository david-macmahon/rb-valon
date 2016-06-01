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

puts 'Synth A'
vs.dump_regs(Valon::Synth::SYNTH_A)
puts
puts 'Synth B'
vs.dump_regs(Valon::Synth::SYNTH_B)
