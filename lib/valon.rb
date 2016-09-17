require 'serialport'
require 'valon/version'

module Valon

  # Class for accesssing Valon synthesizer
  class Synth

    RD = 0x80
    WR = 0x00

    SYNTH_A = 0x00
    SYNTH_B = 0x08

    CMD_REG           = 0x00
    CMD_REF_FREQ      = 0x01
    CMD_LABEL         = 0x02
    CMD_FREQ_RANGE    = 0x03
    CMD_UNDOC         = 0x04 # ???
    CMD_FREQ_SETTINGS = 0x05 # ?
    CMD_CTRL_STATUS   = 0x06
    CMD_WRITE_FLASH   = 0x40

    # Hash mapping commands to data length
    LENGTH = {
      CMD_REG           => 24,
      CMD_REF_FREQ      =>  4,
      CMD_LABEL         => 16,
      CMD_FREQ_RANGE    =>  4,
      CMD_UNDOC         => 12, # ???
      CMD_FREQ_SETTINGS =>  6, # ?
      CMD_CTRL_STATUS   =>  1,
      CMD_WRITE_FLASH   =>  0
    }

    INT_REF = 0x00
    EXT_REF = 0x01

    ACK = 0x06
    NAK = 0x15

    RFLEVEL_TO_DBM = {0 => -4, 1 => -1, 2 => 2, 3 => 5}
    DBM_TO_RFLEVEL = RFLEVEL_TO_DBM.invert

    LOCK_MASK = {SYNTH_A => 0x10, SYNTH_B => 0x20}

    # Hash mapping field name to `[regnum, lsb, nbits]`.
    FIELD_INFO = {
      :int         => [0, 15, 16],
      :frac        => [0,  3, 12],

      :prescaler   => [1, 27,  1],
      :phase       => [1, 15, 12],
      :mod         => [1,  3, 12],

      :noise_mode  => [2, 29,  2],
      :muxout      => [2, 26,  3],
      :ref_dbl     => [2, 25,  1],
      :ref_divby2  => [2, 24,  1],
      :r           => [2, 14, 10],
      :dbl_buf     => [2, 13,  1],
      :cp_current  => [2,  9,  4],
      :ldf         => [2,  8,  1],
      :ldp         => [2,  7,  1],
      :pd_pol      => [2,  6,  1],
      :pwr_down    => [2,  5,  1],
      :cp_tristate => [2,  4,  1],
      :cnt_reset   => [2,  3,  1],

      :cyc_slip    => [3, 18,  1],
      :clkdiv_mode => [3, 15,  2],
      :clkdiv_val  => [3,  3, 12],

      :fb_sel      => [4, 23,  1],
      :rfdiv_sel   => [4, 20,  3],
      :bs_clkdiv   => [4, 12,  8],
      :vco_pwr_dn  => [4, 11,  1],
      :mute_tld    => [4, 10,  1],
      :auxout_sel  => [4,  9,  1],
      :auxout_en   => [4,  8,  1],
      :auxout_pwr  => [4,  6,  2],
      :rfout_en    => [4,  5,  1],
      :rfout_pwr   => [4,  3,  2],

      :ldpin_mode  => [5, 22,  2]
    }

    def initialize(port)
      @port = port
    end

    def serialport(read_timeout=200)
      # Create serial port object
      sp = SerialPort.new(@port, 9600, 8, 1, SerialPort::NONE)
      # Set read timeout (default to 200 ms as is done in the ValonSynth Python
      # library)
      sp.read_timeout = read_timeout

      # Return sp unless block given, yield and then close, otherwise just return it
      return sp unless block_given?

      # Yield sp and then close it
      begin
        return yield sp
      ensure
        sp.close if sp
      end
    end

    # Returns a 1 character String representing checksum byte for `strings`.
    def self.generate_checksum(*strings)
      csum = 0
      strings.each {|s| s.each_byte {|c| csum += c}}
      (csum % 256).chr
    end

    # Returns true if `csum` equals the checksum generated from `strings`.
    def self.checksum_ok?(csum, *strings)
      csum ? csum.chr == generate_checksum(*strings) : false
    end

    # Writes `cmd` plus `data` plus calculated checksum of `data` to Valon
    # synthesizer.  `cmd` is one of `CMD_*` constants.  `data` must be a String
    # of expected length for `cmd`.  `synth` is `SYNTH_A` or `SYNTH_B`.  Some
    # commands ignore `synth`.
    #
    # After writing `cmd` + `data` + checksum, an ACK/NAK byte is read from
    # the Valon synthsizer.  An exception is raised if it is anything other
    # than ACK.
    def write_command(cmd, data='', synth=SYNTH_A)
      # Make sure cmd is valid
      raise "unknown command #{cmd}" unless LENGTH.has_key?(cmd)
      # Verify length of data to write
      if data.length != LENGTH[cmd]
        raise "invalid data length for command #{cmd} " +
              "(expected #{LENGTH[cmd]}, got #{data.length})"
      end
      # Make sure synth has no stray bits set
      synth &= (SYNTH_A|SYNTH_B)

      serialport do |sp|
        cmd = WR|synth|cmd unless cmd == CMD_WRITE_FLASH
        csum = self.class.generate_checksum(cmd.chr, data)
        cmd_data_csum = [cmd, data, csum].pack('CA*A')
        sp.write(cmd_data_csum)
        ack = sp.read(1).ord
        raise "nak error (#{ack == NAK ? 'NAK' : ack.inspect})" if ack != ACK
      end
      nil
    end
    protected :write_command

    # Returns (binary) String containing the response to the read command.
    # `cmd` is one of `CMD_*` constants.  `synth` is `SYNTH_A` or `SYNTH_B`.
    # Some commands ignore `synth`.
    def read_command(cmd, synth=SYNTH_A)
      # Make sure cmd is valid
      raise "unknown command #{cmd}" unless LENGTH.has_key?(cmd)
      # Make sure synth has no stray bits set
      synth &= (SYNTH_A|SYNTH_B)
      # Get length of data to read
      length = LENGTH[cmd]

      serialport do |sp|
        cmd = RD|synth|cmd
        sp.write(cmd.chr)
        data = sp.read(length)
        csum = sp.read(1)
        if !self.class.checksum_ok?(csum, data)
          #p "data=#{data.inspect} (len #{data.length})"
          #p "csum=#{csum.inspect}"
          raise 'checksum error'
        end
        return data
      end
    end
    protected :read_command

    def write_registers(regs, synth=SYNTH_A)
      data = regs.pack('I>6')
      write_command(CMD_REG, data, synth)
    end

    def read_registers(synth=SYNTH_A)
      read_command(CMD_REG, synth).unpack('I>6')
    end

    def write_ref_frequency(ref_freq)
      data = [ref_freq].pack('I>')
      write_command(CMD_REF_FREQ, data)
    end

    def read_ref_frequency
      read_command(CMD_REF_FREQ).unpack('I>')[0]
    end

    def write_label(label)
      data = label.ljust(16)[0...16]
      write_command(CMD_LABEL, data)
    end

    def read_label
      read_command(CMD_LABEL).strip
    end

    def write_freq_range(min_freq, max_freq)
      data = [min_freq, max_freq].pack('S>2')
      write_command(CMD_FREQ_RANGE, data)
    end

    def read_freq_range
      read_command(CMD_FREQ_RANGE).unpack('S>2')
    end

    def write_undoc(undoc)
      data = [undoc].pack('I>')
      write_command(CMD_UNDOC, data)
    end
    protected :write_undoc

    def read_undoc
      read_command(CMD_UNDOC).unpack('I>')
    end
    protected :read_undoc

    def write_freq_settings(fs0, fs1, fs2)
      data = [fs0, fs1, fs2].pack('S>3')
      write_command(CMD_FREQ_SETTINGS, data)
    end
    protected :write_freq_settings

    def read_freq_settings
      read_command(CMD_FREQ_SETTINGS).unpack('S>3')
    end
    protected :read_freq_settings

    def write_ctrl_status(ctrl)
      data = [ctrl].pack('C')
      write_command(CMD_CTRL_STATUS, data)
    end

    def read_ctrl_status
      read_command(CMD_CTRL_STATUS).ord
    end

    def write_flash
      write_command(CMD_WRITE_FLASH)
    end

    # Register related operations

    def get_field(field, synth=SYNTH_A)
      regnum, lsb, nbits = FIELD_INFO[field]
      raise "unknown field '#{field}'" unless regnum
      regs = read_registers(synth)
      mask = (1<<nbits) - 1
      (regs[regnum] >> lsb) & mask
    end

    def set_field(field, value, synth=SYNTH_A)
      regnum, lsb, nbits = FIELD_INFO[field]
      raise "unknown field '#{field}'" unless regnum
      regs = read_registers(synth)
      mask = (1<<nbits) - 1
      regs[regnum] &= ~(mask << lsb)
      regs[regnum] |= (value & mask) << lsb
      write_registers(regs, synth)
      self
    end

    # Dynamically define methods to get/set A/B register fields
    for field in FIELD_INFO.keys
      for synth, prefix in [[SYNTH_A, 'a'], [SYNTH_B, 'b']]
        eval <<-"_end"
          def #{prefix}_#{field}; get_field(:#{field}, #{synth}); end
          def #{prefix}_#{field}=(val); set_field(:#{field}, val, #{synth}); end
        _end
      end
    end

    # Higher level functionality

    def get_dbm(synth=SYNTH_A)
      regs = read_registers(synth)
      rflevel = (regs[4] >> 3) & 0x03
      RFLEVEL_TO_DBM[rflevel]
    end

    def set_dbm(dbm, synth=SYNTH_A)
      rflevel = DBM_TO_RFLEVEL[dbm]
      raise "unsupported dbm #{dbm}" unless rflevel
      regs = read_registers(synth)
      regs[4] &= ~0x18
      regs[4] |= (rflevel << 3)
      write_registers(regs, synth)
    end

    def is_locked?(synth=SYNTH_A)
      if synth != SYNTH_A && synth != SYNTH_B
        raise "invalid synthesizer #{synth}"
      end
      (read_ctrl_status & LOCK_MASK[synth]) != 0
    end

  end # class Synth

  # Return the output divider required to generate the desired frequency
  # `rf_mhz` from within the VCO's frequency range (2200 to 4400 MHz).  Raises
  # an exception if `rf_freq` is below 137.5 MHz or above 4400 MHz.
  def outdiv(rf_mhz)
    case rf_mhz
    when 2200.0..4400.0; return  1
    when 1100.0..2200.0; return  2
    when  550.0..1100.0; return  4
    when  275.0..550.0;  return  8
    when  137.5..275.0;  return 16
    else
      raise 'out of range'
    end
  end
  module_function :outdiv

end
