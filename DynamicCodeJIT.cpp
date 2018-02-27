// here is a piece of code which used JIT to generating x86 code
// xbyak is a leight weight JIT lib i found on GitHub

#ifdef IFU_USE_JIT

#include <xbyak.h>
class BPFoldedGhist : public Xbyak::CodeGenerator {
public:
    BPFoldedGhist() : Xbyak::CodeGenerator(4096) {}

    typedef uint64_t (*FoldFuncPtr)(uint128);
    FoldFuncPtr genFoldFunc(int bits, int len, int bank) {
        if (!(bits < len && len < 128))
            printf("bits=%d, len=%d, bank=%d\n", bits, len, bank);
        assert(len < 128);
        assert(knob_use_v110_tage_cfg); // only support v110 tage fold
        using namespace Xbyak;
        const Reg64 low(rdi), high(rsi), res(rax);
        const Reg64 tmp0(rdx), tmp1(rcx);
        Label start, end;
        align(16);
        L(start);
        mov(res, 0);
        int times = len / bits;
        int low_remain = 64;
        int high_remain = 64;
        for (int n = 0; n < times; n++) {
            xor_(res, low);
            shr(low, bits);
            low_remain -= bits;
            while (low_remain < bits) {
                if (high_remain == 0) {
                    // load next high
                    if (n+1 == times)
                        break;
                    assert(0);
                }
                mov(tmp0, high);
                shl(tmp0, low_remain);
                or_(low, tmp0);
                if (low_remain + high_remain > 64) {
                    high_remain = low_remain;
                    low_remain = 64;
                    shr(high, 64 - high_remain);
                } else {
                    low_remain += high_remain;
                    high_remain = 0;
                }
            }
        }
        mov(tmp0, (1UL << bits) - 1);
        and_(res, tmp0);
        if (len % bits != 0) {
            assert(low_remain > len % bits);
            mov(tmp0, (1UL << (len % bits)) - 1);
            and_(low, tmp0);
            xor_(res, low);
        }
        ret();
        L(end);
        const void *code = start.getAddress();
        return (const FoldFuncPtr)(size_t)(code);
    }
};
#endif // IFU_USE_JIT

uint64_t  BP::GenFoldedGhist(int set_bits, int TageTblHistLen, int bank, uint128 ghr)
{
    uint64_t folded_ghr = 0;

    if (knob_use_v110_tage_cfg) {
        uint64_t mask = (1 << set_bits) - 1;
        int times  = TageTblHistLen / set_bits;
        int remain = TageTblHistLen % set_bits;
        for (int i = 0; i < times; i ++) {
            folded_ghr ^= ghr & mask;
            ghr >>= set_bits;
        }
        if (remain)
            folded_ghr ^= ghr & ((1UL << remain) - 1);
        return folded_ghr;
    } else {
        int times_value = (int)(TageTblHistLen / set_bits);
        bool remainder_value = (bool)(TageTblHistLen % set_bits);
        int total_iter_cnt  = times_value + (int)remainder_value;

        for (int i = 0; i < (total_iter_cnt-1); ++i){
            folded_ghr = (folded_ghr ^ (ghr>>(int)(i*set_bits))) & ((1<<set_bits)-1);
        }

        if(total_iter_cnt){
            int shift_bit = (int)((total_iter_cnt-1)*set_bits);
            folded_ghr = (folded_ghr ^ 
                    ((ghr>>shift_bit) & 
                     ((1<<(TageTblHistLen-shift_bit)) - 1))) 
                & ((1<<set_bits)-1);
        }
    }

    return folded_ghr;
}
