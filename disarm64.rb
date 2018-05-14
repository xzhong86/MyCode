#!/usr/bin/env ruby

# 1. get A64 XML and SysReg XML from:
#   https://developer.arm.com/products/architecture/a-profile/exploration-tools
# 2. run script to get data
#   ./disarm64.rb --sreg-dir SysReg8.3/ --isa-dir ISA8.3/ --save data.yaml
# 3. get assembler fast with data.yaml
#   ./disarm64.rb --load data.yaml [--pc 80010000] 0xd51ccc02 0xd51ccc03 ...

require 'optparse'
require 'ostruct'

require 'yaml'
require 'rexml/document'

$bin_dir = File.expand_path('..', __FILE__)

fail "At Last ruby 2.1 is needed." if RUBY_VERSION < "2.1.0"

class Fixnum
  def extract(msb, len)
    val = self >> (msb - len + 1)
    val & ((1 << len) - 1)
  end
end

class String
  # example: 'xx101xx01' contains '10101x101'
  def coding_contains(str)
    return false if self.size != str.size
    self.size.times do |i|
      return false if self[i] != str[i] && self[i] != 'x'
    end
    true
  end
end

class REXML::Element
  def attr(name)
    self.attributes[name]
  end
  def attrs_at(*names)
    names.map{|n| attr(n) }
  end
end

class RegDiagram
  class Field
    attr_reader :hibit, :width, :name
    def initialize(x)
      @hibit = x.attributes['hibit'].to_i
      @width = (x.attributes['width'] || '1').to_i
      @name = x.attributes['name']
      cols = x.get_elements('c')
      if cols.size > 1
        @vstr = cols.map{|e| e.text }.join
      else
        @vstr = cols.first.text
      end
      if @vstr =~ /!= *([01x]+)/
        @nstr = $1
        @vstr = nil
      end
      if @vstr =~ /\([01]\)/
        @vstr.gsub!(/\([01]\)/, 'x')
      end
      fail "vstr=#{@vstr}" if @vstr and @vstr.length != @width
      fail "nstr=#{@nstr}" if @nstr and @nstr.length != @width
    end

    def match(val)
      (!@vstr or @vstr.coding_contains(val)) and
        (!@nstr or !@nstr.coding_contains(val))
    end

    def coding_str
      @vstr || 'x' * @width
    end
    def to_s
      if @name && @vstr
        "<0b#{@vstr}.#{@name}>"
      elsif @name
        "<#{@width}.#{@name}>"
      else
        coding_str
      end
    end
  end

  def initialize(x)
    @fields = []
    @width = x.attributes['form'].to_i
    x.each_element('box'){ |e| @fields << Field.new(e) }
  end

  def match(bin_str)
    fail "Must be string" if not bin_str.kind_of? String
    @fields.each do |f|
      subv = val[@width - f.hibit - 1, f.width]
      return false if not f.match(subv)
    end
    true
  end

  def decompose(code_val)
    @fields.select{|f| f.name}.map do |f|
      [ f.name.to_sym, code_val.extract(f.hibit, f.width) ]
    end.to_h
  end
  def coding_str
    @fields.map{|f| f.coding_str}.join
  end
  def to_s
    @fields.map{|f| f.to_s}.join
  end
end

class XMLInst
  attr_reader :name, :fname, :type, :disfmt
  def initialize(fname, xinst, xiclass)
    @fname = fname
    @name, @type = xinst.attrs_at('id', 'type')
    @regdiagram = RegDiagram.new(xiclass.elements['regdiagram'])

    coding_str = @regdiagram.coding_str
    @code_mask  = coding_str.tr('01x','110').to_i(2)
    @code_value = coding_str.tr('x','0').to_i(2)

    xtemp = xiclass.elements['encoding/asmtemplate']
    @disfmt = xtemp.get_elements('*').map{|e| e.text}.join
  end
  def match(code)
    (code & @code_mask) == @code_value
  end
  def decompose(code)
    @regdiagram.decompose(code)
  end
  def to_s
    @regdiagram.to_s
  end
end

def read_isa_xml_files(isa_dir)
  insts = []
  count = { total: 0, failed: 0, succed: 0 }
  Dir.glob(isa_dir + '/*.xml').sort.each do |file|
    count[:total] += 1
    File.open(file, 'r:utf-8') do |fio|
      doc = REXML::Document.new fio
      xinst = doc.elements['/instructionsection']
      if xinst && xinst.attributes['type'] != 'pseudocode'
        #puts "reading #{file}"
        xiclasses = xinst.get_elements('classes/iclass')
        puts "iclass not found in #{file}" if xiclasses.empty?
        xiclasses.each do |xi|
          insts << XMLInst.new(file, xinst, xi)
        end
        count[:succed] += 1
      else
        puts "read #{file} failed."
        count[:failed] += 1
      end
    end
  end
  p count
  puts "Total get #{insts.size} insts."
  insts
end

class XMLSysReg
  attr_reader :enc_str, :fname
  def initialize(file, xregpage, xreg)
    @fname = file
    @asmvar, @enc = {}, {}
    xacci = xreg.elements['access_mechanisms//access_instructions']
    xacci.each_element('defvar/def') do |xdef|
      asmname, asmvalue = xdef.attrs_at(*%w[asmname asmvalue])
      if not asmvalue
        xe = xdef.elements['enc']
        asmvalue = '*' + xe.attr('varname')
        @enc[xe.attr('n')] = xe.attr('v') || 'x' * xe.attr('width').to_i
      else
        xdef.each_element('enc') do |xe|
          @enc[xe.attr('n')] = xe.attr('v') || 'x' * xe.attr('width').to_i
        end
      end
      @asmvar[asmname] = asmvalue
    end
    @inst = xacci.elements['access_instruction'].attr('id')
    @enc_str = @enc.values_at(*%w[op0 op1 CRn CRm op2]).join
    if @enc_str.length == 16 || @enc_str.length == 14
      @enc_mask  = @enc_str.tr('01x','110').to_i(2)
      @enc_value = @enc_str.tr('x','0').to_i(2)
    else
      fail "bad enc #{@enc_str} for #{@inst}"
    end
  end
  def match(enc)
    (enc & @enc_mask) == @enc_value
  end
  def match_val
    @enc_str.count '01'
  end
  def name
    @asmvar['systemreg'] || enc_name
  end
  def enc_name
    encval = @enc.each.map{|k,v| [k.to_sym,v.to_i(2)]}.to_h
    encval[:op0] ||= 0
    'S%{op0}_%{op1}_C%{CRn}_C%{CRm}_%{op2}' % encval
  end
end

def read_sysreg_xml_files(xmldir)
  regs = []
  count = { total: 0, skip: 0, failed: 0, succed: 0 }
  Dir.glob(xmldir + '/*.xml').sort.each do |file|
    count[:total] += 1
    File.open(file, 'r:utf-8') do |fio|
      doc = REXML::Document.new fio
      xpage = doc.elements['/register_page']
      xreg = xpage && xpage.elements['registers/register']
      if xreg and not xreg.elements['access_mechanisms']
        puts "skip #{file}"
        count[:skip] += 1
      elsif xreg && xreg.attributes['execution_state'] == 'AArch64'
        puts "reading #{file}"
        xregs = xpage.get_elements('registers/register')
        puts "register not found in #{file}" if xregs.empty?
        xregs.each do |xr|
          regs << XMLSysReg.new(file, xpage, xr)
        end
        count[:succed] += 1
      else
        puts "read #{file} failed."
        count[:failed] += 1
      end
    end
  end
  p count
  puts "Total get #{regs.size} SysRegs."
  regs
end

class SysRegParser
  def initialize(sregs)
    @sregs = sregs
    #@htable = sregs.map{|s| [s.enc_name, s] }.to_h
  end
  def get_name(fields) # param like { op0: 3, CRn: 10, ...}
    enc_fld = fields.values_at(:op0, :op1, :CRn, :CRm, :op2)
    enc_val = ("%02b%03b%04b%04b%03b" % enc_fld).to_i(2)
    regs = @sregs.select{|s| s.match(enc_val) }
    reg = regs.max_by{|s| s.match_val }
    reg.name.tr('<>', '[]')
  end
end

def read_instruction(xmlfile)
  insts = []
  doc = REXML::Document.new File.new(xmlfile)
  xinst = doc.elements["/instructionsection"]
  p xinst, doc.root
  xiclasses = xinst.get_elements('classes/iclass')
  if xinst && xinst.attributes['type'] != 'pseudocode'
    puts "reading #{xmlfile}"
    xiclasses.each do |xi|
      insts << XMLInst.new(xmlfile, xinst, xi)
    end
  end
end

def disarm(code, inst, sregp)
  items = inst.decompose(code)
  fmt = inst.disfmt.gsub(/<[WX]([dmnt])>/, 'R<R\1>')
  case inst.name
  when 'MSR_imm'
    fmt = 'MSR PStateField, #%{CRm}'
  when 'MSR_reg', 'MRS'
    items[:op0] = items[:o0] + 2
    name = sregp.get_name(items)
    if inst.name == 'MRS'
      fmt = "MRS R<Rt>, #{name}"
    else
      fmt = "MSR #{name}, R<Rt>"
    end
  else
  end
  fmt.gsub(/<(\w+)>/) do |fld|
    sym = $1.to_sym
    items.has_key?(sym) ? items[sym] : $&
  end
end 

# main
opt = OpenStruct.new
OptionParser.new do |opts|
  opts.banner = "disarm64 [options] code..."
  opts.on('--isa-dir DIR', 'specify ARM ISA XML dir') { |d| opt.isa_dir = d }
  opts.on('--sreg-dir DIR', 'specify ARM SysReg dir') { |d| opt.sreg_dir = d }
  opts.on('--save data.yaml', 'save XML data') { |f| opt.save_file = f }
  opts.on('--load data.yaml', 'load YAML data') { |f| opt.load_file = f }
  opts.on('--pc PC', 'specify PC for insts') { |o| opt.pc = o }
  opts.on('--show ASM', 'show details which match ASM') { |a| opt.show = a }
  opts.on('--debug', 'debug script') { opt.debug = true }
end.parse!

$insts = []
$sregs = []

unless opt.load_file and opt.isa_dir
  opt.load_file = $bin_dir + '/.disarm-data.yaml'
  fail 'need data file or ISA dir' if not File.exist? opt.load_file
end

if opt.load_file
  $insts, $sregs = YAML.load(File.open(opt.load_file, 'r'))
end
if opt.isa_dir
  $insts = read_isa_xml_files(opt.isa_dir)
end
if opt.sreg_dir
  $sregs = read_sysreg_xml_files(opt.sreg_dir)
end
if opt.save_file
  File.open(opt.save_file, 'w').write(YAML.dump([$insts, $sregs]))
end

if opt.show
  $insts.each do |inst|
    if inst.name.match opt.show
      puts "#{inst.name}: #{inst.disfmt}"
      puts inst
    end
  end
end

puts "Total #{$insts.size} Inst, #{$sregs.size} Regs."

sregp = SysRegParser.new $sregs

pc = opt.pc.hex if opt.pc
pc ||= 0

ARGV.each do |code|
  count = 0
  if code =~ /(\h+):(\h+)/
    pc, code = $1.hex, $2.hex
  else
    code = code.hex
  end
  $insts.each do |inst|
    if inst.match(code)
      #puts "match inst #{inst.name}"
      asm = disarm(code, inst, sregp)
      printf "%08x:%08x #{asm}\n", pc, code
      count += 1
    end
  end
  pc += 4
  puts "No Inst match #{code}" if count == 0
end

# 0xd51ccc02 # MSR
# 0xd53ccc02 # MRS
