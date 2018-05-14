#!/usr/bin/env ruby

require 'ostruct'
require 'optparse'

def bmp_read_head(fio)
  titles = %i[ type size res1 res2 offset ]
  fields = fio.read(14).unpack('a2LS2L');
  OpenStruct.new [ titles, fields ].transpose.to_h
end

def bmp_read_bitinfo(fio)
  titles = %i[ size width height planes bitcount compression
               sizeimage xppm yppm clrused clrimp ]
  fields = fio.read(40).unpack('L3S2L6')
  OpenStruct.new [ titles, fields ].transpose.to_h
end

def open_bmp(file)
  fh = File.open(file)
  h = bmp_read_head(fh)
  p h
  info = bmp_read_bitinfo(fh)
  p info
end

class DecodeBMP
  class Pixel
    def initialize(b, r, g)
      @r, @g, @b = r, g, b
    end
    def to_value(mode)
      fail if mode != :mode_4bit
      val  =  (@b >> 7) & 1
      val |= ((@g >> 7) & 1) << 1
      val |= ((@r >> 6) & 3) << 2
      val
    end
    def to_s
      "r:#{@r} g:#{@g} b:#{@b}"
    end
    def is_white
      @r > 0xf8 and @g > 0xf8 and @b > 0xf8
    end
    def is_black
      @r < 0x8 and @g < 0x8 and @b < 0x8
    end
  end

  def initialize(fname)
    @fin = File.open fname, 'r'
    head = bmp_read_head @fin
    p head
    fail "Bad BMP file" if head.type != 'BM'
    @bf_offset = head.offset
    @info = bmp_read_bitinfo @fin
    p @info
    fail "Bad format not 24bit" if @info.bitcount != 24
    @row_size = @info.width * 3
    @row_size += 4 - @row_size % 4 if @row_size % 4 != 0
    @mode = :mode_4bit
  end

  def dump_pixel(x, y)
    pix = get_pixel(x, y)
    val = pix.to_value(@mode)
    puts "pixel at x=#{x},y=#{y}: #{pix} value=#{val}"
  end

  def get_pixel(x, y)
    offset = @bf_offset + y * @row_size + x * 3
    @fin.seek offset if @fin.tell != offset
    brg = @fin.read(3).unpack('CCC')
    Pixel.new *brg
  end
end

# main
opt = OpenStruct.new
opt.pixels = []
OptionParser.new do |opts|
  opts.banner = "readbmp.rb [options] file"
  opts.on('p','--pixel X,Y', 'specify pixel to dump') { |s|
    opt.pixels << [$1.to_i,$2.to_i] if s =~ /(\d+),(\d+)/
  }
end.parse!

file = ARGV[0]
dec = DecodeBMP.new file
opt.pixels.each do |p|
  dec.dump_pixel(p[0], p[1])
end

#open_bmp file
