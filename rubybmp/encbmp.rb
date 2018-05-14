#!/usr/bin/env ruby

require 'ostruct'
require 'optparse'

# for 24bit BitMap file
def gen_24bit_bmp_header(fio, width, height)
  row_size = 3 * width
  if row_size % 4 != 0
    row_size += 4 - row_size % 4
  end
  image_size = height * row_size
  total_size = image_size + 54
  fio.write([ 'BM', total_size, 0, 0, 54 ].pack('a2LS2L'))
  fio.write([ 40, width, height, 1, 24, 0, image_size, 0,0,0,0 ].pack('L3S2L6'))
end

class EncodeBMP
  def initialize(fname, w, h)
    @width, @height = w, h
    @biWidth, @biHeight = w + 8, h + 4
    @fout = File.open fname,'w'
    @black = [ 0,0,0 ] ; @white = [ 255,255,255 ]
    @row_begin = [ @white, @white, @black, @white ].flatten
    @row_end = [ @white, @black, @white, @white ].flatten
    @mode = :mode_4bit # :mode_6bit :mode_8bit
    write_header
  end
  def write_header
    puts "Create image #{@biWidth}x#{@biHeight}"
    gen_24bit_bmp_header @fout, @biWidth, @biHeight
    @biWidth.times{ @fout.write @white.pack('ccc') }
    @biWidth.times{ @fout.write @black.pack('ccc') }
    @x, @y = 0, 2
    1.upto(@width){ |v| draw_val_pixel(v) }
    fail "y=#{@y} x=#{@x}" if @y != 3 or @x != 0
  end
  def fill_end
    count = 0
    while @y < @biHeight
      draw_pixel(*@black)
      count += 1
    end
    puts "total #{count} bytes filled at end."
  end

  def draw_pixel(r, g, b)
    fail "y=#{@y} out of range" if @y >= @biHeight
    fail "x=#{@x} out of range" if @x >= @biWidth
    if @x == 0 && @y < @biHeight
      @fout.write @row_begin.pack("c*")
      @x += 4
    end
    @fout.write([b,r,g].pack('ccc'))
    @x += 1
    if @x == @biWidth - 4
      @fout.write @row_end.pack("c*")
      @x = 0 ; @y += 1
      return if @y == @biHeight
    end
  end
  def draw_val_pixel(v)
    if @mode == :mode_4bit # 2 1 1
      r = (v >> 2) & 3
      r = (r << 6) | 0x1f
      g = (v >> 1) & 1
      g = (g << 7) | 0x3f
      b = v & 1
      b = (b << 7) | 0x3f
    elsif @mode == :mode_6bit # 2 2 2
      r = (v >> 4) & 3
      r = (r << 6) | 0x1f
      g = (v >> 2) & 3
      g = (g << 6) | 0x1f
      b = v & 3
      b = (b << 6) | 0x1f
    elsif @mode == :mode_8bit # 3 3 2
      r = (v >> 5) & 7
      r = (r << 5) | 0xf
      g = (v >> 2) & 7
      g = (g << 5) | 0xf
      b = v & 3
      b = (b << 6) | 0x1f
    else
      fail "unsupported mode #{@mode}"
    end
    draw_pixel(r, g, b)
  end
  
  def draw_data(data_in)
    puts "coding data into #{@width}x#{@height}"
    count = 0
    data_in.each_byte do |dat|
      if @mode == :mode_4bit
        draw_val_pixel (dat >> 4) & 0xf
        draw_val_pixel dat & 0xf
        count += 1
      else
        fail "unsupported mode #{@mode} when spliting"
      end
    end
    puts "total #{count} bytes coded."
    fill_end
  end
end

# main
opt = OpenStruct.new
OptionParser.new do |opts|
  opts.banner = "encbmp.rb [options]"
  opts.on('i','--input FILE', 'specify input file') { |f| opt.input = f }
  opts.on('o','--output FILE', 'specify output file') { |f| opt.output = f }
  opts.on('w','--width N', 'specify image width') { |w| opt.width = w.to_i }
  opts.on('m','--mode M', '4bit/6bit/8bit') { |m| opt.mode = m }
end.parse!

fail "missing input file" if not opt.input
fail "missing output file" if not opt.output
opt.mode ||= '4bit'
fail "#{opt.mode} not supported" if opt.mode != '4bit'

opt.mode = ('mode_' + opt.mode).to_sym

#fin = File.open "data.xz", 'rb'
fin = File.open opt.input, 'rb'
size = File.size fin
size = size * 2 # 4bit mode

# output 16:9 image
width = opt.width
if not width
  fact = Math.sqrt(size.to_f / (16*9))
  width = (fact * 16).ceil
end
height = (size + width - 1) / width

bcan = EncodeBMP.new opt.output, width, height
bcan.draw_data fin

