require 'serialport'
require 'valon/version'

module Valon

  module Constants
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
  end # module Constants

  include Constants

  def normalize_regs(regs)
    if !(Array === regs) || regs.length != 6
      raise 'register data must be Array of length 6'
    end
    regs.pack('I>6').unpack('I>6')
  end
  module_function :normalize_regs

  # Returns a 1 character String representing checksum byte for `strings`.
  def generate_checksum(*strings)
    csum = 0
    strings.each {|s| s.each_byte {|c| csum += c}}
    (csum % 256).chr
  end
  module_function :generate_checksum

  # Returns true if `csum` equals the checksum generated from `strings`.
  def checksum_ok?(csum, *strings)
    csum ? csum.chr == generate_checksum(*strings) : false
  end
  module_function :checksum_ok?

  # Register related operations

  def get_field(regs, field)
    regnum, lsb, nbits = FIELD_INFO[field]
    raise "unknown field '#{field}'" unless regnum
    mask = (1<<nbits) - 1
    (regs[regnum] >> lsb) & mask
  end
  module_function :get_field

  def set_field(regs, field, value)
    regnum, lsb, nbits = FIELD_INFO[field]
    raise "unknown field '#{field}'" unless regnum
    mask = (1<<nbits) - 1
    regs[regnum] &= ~(mask << lsb)
    regs[regnum] |= (value & mask) << lsb
  end
  module_function :set_field

  # Return the output divider selector required to generate the desired
  # frequency `rf_mhz` from within the VCO's frequency range (2200 to 4400
  # MHz).  Raises an exception if `rf_freq` is below 137.5 MHz or above 4400
  # MHz.  The output divider selector os log2 of the output divider.
  def outdiv_sel(rf_mhz)
    case rf_mhz
    when 2200.0..4400.0; return 0
    when 1100.0..2200.0; return 1
    when  550.0..1100.0; return 2
    when  275.0..550.0;  return 3
    when  137.5..275.0;  return 4
    else
      raise "#{rf_mhz} MHz is out of range [137.5 to 4400.0]"
    end
  end
  module_function :outdiv_sel

  # Return the output divider required to generate the desired frequency
  # `rf_mhz` from within the VCO's frequency range (2200 to 4400 MHz).  Raises
  # an exception if `rf_freq` is below 137.5 MHz or above 4400 MHz.
  def outdiv(rf_mhz)
    1 << outdiv_sel(rf_mhz)
  end
  module_function :outdiv

  def set_freq_rf(regs, hz, ref_hz=10_000_000)
    # Limit to integer Hz
    hz = hz.round
    ref_hz = ref_hz.round

    # Get outdiv selector (validates `hz`) and set that field
    outdivsel = outdiv_sel(hz/1e6)
    set_field(regs, :rfdiv_sel, outdivsel)

    # Set ref doubler, clear ref div-by-2, set R counter to 1.  It's posible
    # that some ref freqs could make these choices invalid.  If that's ever
    # discovered to be a problem, this logic will have to be smarter.
    set_field(regs, :ref_dbl, 1)
    set_field(regs, :ref_divby2, 0)
    set_field(regs, :r, 1)
    # Calculate "phase frequency detector" frequency
    f_pfd = 2 * ref_hz
    # Set bs_clkdiv to ensure max "band select clock" freq of 125 kHz
    set_field(regs, :bs_clkdiv, (f_pfd/125e3).ceil)
    # Set feedback select to use VCO output directly
    set_field(regs, :fb_sel, 1)
    # Compute f_vco
    f_vco = hz << outdivsel
    # Compute int, frac_mod
    int, frac_mod = Rational(f_vco, f_pfd).divmod(1)
    # Set int, frac, and mod fields
    # TODO set int_n field if appropriate?
    set_field(regs, :int, int)
    set_field(regs, :frac, frac_mod.numerator)
    set_field(regs, :mod, frac_mod.denominator)
    # Set other misc fields
    set_field(regs, :phase, 1) # recommended
    set_field(regs, :noise_mode, 0) # low noise
  end
  module_function :set_freq_rf

  # Class for accesssing Valon synthesizer
  class Synth

    include Constants

    def initialize(port)
      @debug = false
      @port = port
      read_registers
    end

    attr_reader :a_regs
    attr_reader :b_regs

    attr_accessor :debug

    def a_registers=(regs)
      @a_regs = Valon.normalize_regs(regs)
    end

    def b_registers=(regs)
      @b_regs = Valon.normalize_regs(regs)
    end

    def registers=(*regs)
      ar, br = *regs
      ar = Valon.normalize_regs(ar) if ar
      br = Valon.normalize_regs(br) if br
      @a_regs = ar if ar
      @b_regs = br if br
    end

    def registers(synth=nil)
      case synth
      when SYNTH_A, 0; @a_regs
      when SYNTH_B, 1; @b_regs
      when nil; [@a_regs, @b_regs]
      else raise "invalid synthesizer #{synth}"
      end
    end

    def serialport(read_timeout=200)
      # Create serial port object
      sp = SerialPort.new(@port, 9600, 8, 1, SerialPort::NONE)
      # Turn off flow control
      sp.flow_control = SerialPort::NONE
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
        csum = Valon.generate_checksum(cmd.chr, data)
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
        if @debug
          print"data"
          data.each_char {|c| print " %02x" % c.ord}
          puts csum ? "\ncsum %02x" % csum.ord : "\ncsum --"
        end
        if !csum || !Valon.checksum_ok?(csum, data)
          #p "data=#{data.inspect} (len #{data.length})"
          #p "csum=#{csum.inspect}"
          raise 'checksum error'
        end
        return data
      end
    end
    protected :read_command

    def write_registers(synth=nil)
      # If not writing only to synth B
      if synth != SYNTH_B
        a_data = @a_regs.pack('I>6')
        write_command(CMD_REG, a_data, SYNTH_A)
      end
      # If not writing only to synth A
      if synth != SYNTH_A
        b_data = @b_regs.pack('I>6')
        write_command(CMD_REG, b_data, SYNTH_B)
      end
    end

    def read_registers
      @a_regs = read_command(CMD_REG, SYNTH_A).unpack('I>6')
      @b_regs = read_command(CMD_REG, SYNTH_B).unpack('I>6')
      self
    end

    def ref_frequency=(ref_freq)
      data = [ref_freq].pack('I>')
      write_command(CMD_REF_FREQ, data)
    end
    alias ref_freq= ref_frequency=

    def ref_frequency
      read_command(CMD_REF_FREQ).unpack('I>')[0]
    end
    alias ref_freq ref_frequency

    def label=(label)
      data = label.ljust(16)[0...16]
      write_command(CMD_LABEL, data)
    end

    def label
      read_command(CMD_LABEL).strip
    end

    # Set VCO frequency range.  `minmax_mhz` can be Array or Range (or anything
    # else that responds to #first and #last.  `minmax_mhz.first` is minimum
    # VCO frequency (in MHz); `minmax_mhz.last` is maximum (in MHz).  These
    # values are not used by the synthesizer itself.  They are merley
    # informative values for humans or configuration software.
    def vco_range=(minmax_mhz)
      data = [minmax_mhz.first, minmax_mhz.last].pack('S>2')
      write_command(CMD_FREQ_RANGE, data)
    end

    # Return `[min_mhz, max_mhz]` VCO frequencies (in MHz).
    def vco_range
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

    def ctrl_status=(ctrl)
      data = [ctrl].pack('C')
      write_command(CMD_CTRL_STATUS, data)
    end

    def ctrl_status
      read_command(CMD_CTRL_STATUS).ord
    end

    def write_flash
      write_command(CMD_WRITE_FLASH)
    end

    # Dynamically define methods to get/set A/B register fields
    for field in FIELD_INFO.keys
      for prefix in ['a', 'b']
        eval <<-"_end"
          def #{prefix}_#{field}; Valon.get_field(@#{prefix}_regs, :#{field}); end
          def #{prefix}_#{field}=(val); Valon.set_field(@#{prefix}_regs, :#{field}, val); end
        _end
      end
    end

    # Higher level functionality

    def get_dbm
      [RFLEVEL_TO_DBM[a_rfout_pwr], RFLEVEL_TO_DBM[b_rfout_pwr]]
    end

    # Return output power of syntheisizer A (in dBm).
    def a_dbm
      get_dbm[0]
    end

    # Return output power of syntheisizer B (in dBm).
    def b_dbm
      get_dbm[1]
    end

    # Set output power of specified syntheisizer (in dBm).
    # `dbm` can be -4, -1, +2, or +5.
    def set_dbm(dbm, synth)
      rflevel = DBM_TO_RFLEVEL[dbm]
      raise "unsupported dbm #{dbm}" unless rflevel
      Valon.set_field(registers(synth), :rfout_pwr, rflevel)
    end

    # Set output power of syntheisizer A (in dBm).
    # `dbm` can be -4, -1, +2, or +5.
    def a_dbm=(dbm)
      set_dbm(dbm, SYNTH_A)
    end

    # Set output power of syntheisizer B (in dBm).
    # `dbm` can be -4, -1, +2, or +5.
    def b_dbm=(dbm)
      set_dbm(dbm, SYNTH_B)
    end

    # Returns true if the synthesizer is configured to use the external
    # reference
    def is_ext_ref?
      (ctrl_status & EXT_REF) != 0
    end

    def ext_ref=(extref)
      self.ctrl_status = extref ? EXT_REF : INT_REF
    end

    def is_locked?(synth)
      if synth != SYNTH_A && synth != SYNTH_B
        raise "invalid synthesizer #{synth}"
      end
      (ctrl_status & LOCK_MASK[synth]) != 0
    end

    def is_a_locked?
      is_locked?(SYNTH_A)
    end

    def is_b_locked?
      is_locked?(SYNTH_B)
    end

    def freq_pfd(synth, ref_in=nil)
      ref_in ||= ref_frequency
      ref_in = 10_000_000 if ref_in == 0
      d = Valon.get_field(registers(synth), :ref_dbl)
      t = Valon.get_field(registers(synth), :ref_divby2)
      r = Valon.get_field(registers(synth), :r)
      r = 1 if r == 0
      f_pfd = ref_in * Rational(1+d, r*(1+t))
      f_pfd.denominator == 1 ? f_pfd.to_i : f_pfd
    end

    def freq_a_pfd
      freq_pfd(SYNTH_A)
    end

    def freq_b_pfd
      freq_pfd(SYNTH_B)
    end

    # Assumes that feedback is the fundamental (i.e. not divided)
    def freq_vco(synth)
      f_pfd = freq_pfd(synth)
      int = Valon.get_field(registers(synth), :int)
      frac = Valon.get_field(registers(synth), :frac)
      mod = Valon.get_field(registers(synth), :mod)
      mod = 1 if mod == 0
      f_vco = f_pfd * (int + Rational(frac,mod))
      f_vco.denominator == 1 ? f_vco.to_i : f_vco.denominator
    end

    def freq_a_vco
      freq_vco(SYNTH_A)
    end

    def freq_b_vco
      freq_vco(SYNTH_B)
    end

    def freq_rf(synth)
      f_vco = freq_vco(synth)
      outdiv = 1 << Valon.get_field(registers(synth), :rfdiv_sel)
      f_rf = Rational(f_vco, outdiv)
      f_rf.denominator == 1 ? f_rf.to_i : f_rf
    end

    def freq_a_rf
      freq_rf(SYNTH_A)
    end

    def freq_b_rf
      freq_rf(SYNTH_B)
    end

    # Set output frequency of synthesizer A to `hz` Hz.
    def freq_a_rf=(hz, ref_in=nil)
      ref_in ||= ref_frequency
      ref_in = 10_000_000 if ref_in == 0
      Valon.set_freq_rf(@a_regs, hz, ref_in)
    end

    # Set output frequency of synthesizer A to `hz` Hz.
    def freq_b_rf=(hz, ref_in=nil)
      ref_in ||= ref_frequency
      ref_in = 10_000_000 if ref_in == 0
      Valon.set_freq_rf(@b_regs, hz, ref_in)
    end

  end # class Synth

end
