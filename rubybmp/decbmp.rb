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
    fail "Bad BMP file" if head.type != 'BM'
    @bf_offset = head.offset
    @info = bmp_read_bitinfo @fin
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
  def check_mark_line(y, startx, endx)
    puts "check line y=#{y} startx=#{startx} endx=#{endx}"
    return false if !get_pixel(startx, y).is_white ||
                    !get_pixel(startx+1, y).is_white ||
                    !get_pixel(startx+2, y).is_black ||
                    !get_pixel(startx+3, y).is_white
    return false if !get_pixel(endx, y).is_white ||
                    !get_pixel(endx-1, y).is_white ||
                    !get_pixel(endx-2, y).is_black ||
                    !get_pixel(endx-3, y).is_white
    datax = startx + 4
    (datax).upto(datax + 14) do |x|
      return false if get_pixel(x, y).to_value(@mode) != x - datax + 1
    end
    @data = OpenStruct.new({ startx: datax, endx: endx - 4, starty: y+1 })
    true
  end
  def find_data
    0.upto(@info.height - 1) do |y|
      blk_start = blk_end = nil
      blk_prev = nil
      0.upto(@info.width - 1) do |x|
        pix = get_pixel(x, y)
        if pix.is_black
          if x - 1 != blk_prev
            blk_start = x
          end
          blk_prev = x
        elsif blk_start
          blk_end = blk_prev
        end
      end
      if blk_start
        blk_end ||= @info.width - 1
        if blk_end - blk_start > 100 && check_mark_line(y+1, blk_start, blk_end)
          break
        end
      end
    end
    puts "find data #{@data.to_h}" if @data
    @data ? true : false
  end
  def decode_data(output)
    fail if @mode != :mode_4bit
    out = File.open output, 'w'
    count = value = 0
    @data.starty.upto(@info.height-1) do |y|
      @data.startx.upto(@data.endx) do |x|
        pix = get_pixel(x, y)
        if pix.is_black
          puts "total #{count/2} bytes write."
          out.close
          return
        end
        if count % 2 == 1
          value = (value << 4) | pix.to_value(@mode)
          out.write [value].pack('c')
        else
          value = pix.to_value(@mode)
        end
        count += 1
      end
    end
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
OptionParser.new do |opts|
  opts.banner = "decbmp.rb [options]"
  opts.on('i','--input FILE', 'specify input file') { |f| opt.input = f }
  opts.on('o','--output FILE', 'specify output file') { |f| opt.output = f }
  opts.on('m','--mode M', '4bit/6bit/8bit') { |m| opt.mode = m }
end.parse!

fail "missing input file" if not opt.input
fail "missing output file" if not opt.output
opt.mode ||= '4bit'
fail "#{opt.mode} not supported" if opt.mode != '4bit'

opt.mode = ('mode_' + opt.mode).to_sym

dec = DecodeBMP.new opt.input
if dec.find_data
  dec.decode_data opt.output
end

#open_bmp opt.input
