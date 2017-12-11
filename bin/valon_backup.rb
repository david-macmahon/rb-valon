#!/usr/bin/env ruby

# Just dump the register contents in hex and binary.

require 'valon'
require 'yaml'

vs = Valon::Synth.new(ARGV[0]||'/dev/ttyUSB0')

if vs.registers_valid?(true)
  puts "# Backup of '#{vs.label}' #{DateTime.now}"
  puts vs.registers.to_yaml
else
  puts "# Unwilling to backup invalid registers"
end
