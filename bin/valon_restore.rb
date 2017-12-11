#!/usr/bin/env ruby

# Restore Valon synth registers from YAML backup file
# (as created by valong_backup.rb)

require 'valon'
require 'yaml'

if ARGV.empty?
  puts "usage: #{File.basename $0} BACKUP_FILE [PORT]"
  exit 1
end

regs = YAML.load_file(ARGV[0])

unless Array === regs
  puts "did not get Array from backup file"
  exit 1
end

if regs.length != 2
  puts "got length #{regs.length} Array, expected 2"
  exit 1
end

if regs[0].length != 6 or regs[1].length != 6
  puts "register arrays must have length 6"
  exit 1
end

vs = Valon::Synth.new(ARGV[1]||'/dev/ttyUSB0')

vs.a_registers = regs[0]
vs.b_registers = regs[1]

vs.write_flash if vs.registers_valid?
