
out_bin = out.bin
out_bmp = output.bmp
in_bmp = output.bmp #test-3.bmp

all: $(out_bmp) $(out_bin) dump

$(out_bmp): data.xz encbmp.rb
	./encbmp.rb -i $< -o $@

$(out_bin): $(in_bmp) decbmp.rb
	./decbmp.rb -i $< -o $@

.PHONY: dump
dump:
	xxd data.xz > dump.in.txt
	xxd $(out_bin) > dump.out.txt


