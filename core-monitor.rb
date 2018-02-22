

class TraceCore < TraceModule

  def build ()
    block("ooo", "u_oex.u_ooo") {
      block("dec1", "u_ooo_dec.u_ooo_dec1") {
        4.times { |n|
          group("inst#{n}", "D1") {
            valid  "vld"   , "inst_vld_#{n}_d1"
            signal "rid"   , "rid_#{n}_d1", 8
            signal "rcnt"  , "rslv_num_#{n}_d1", 4
            signal "pc_idx", "pc_dec_pc_idx_#{n}_d1", 5
            signal "pc_off", "pc_dec_pc_offset_#{n}_d1", 6
            signal "inst"  , "ifu_ooo_inst_#{n}_d1", 32
            message "inst#{n} rcnt=%{rcnt} pc_idx=%{pc_idx} pc_off=%{pc_off}"
          }
        }
      }

      block("pc", "u_ooo_pc") {
        4.times { |n|
          group("write#{n}", "D2") {
            unit "PC_BUF"
            valid  "vld"   , "pc_wren_#{n}_d2"
            signal "ptr"   , "pc_wrptr_cs_ff", 5
            signal "data"  , "pc_wr_data_#{n}_d2", 48, 2
            message "pc write#{n} ptr=%{ptr} data=%{data}"
          }
        }
      }

      block("int_atag") {
        4.times { |n|
          group("uop#{n}", "D3") {
            valid  "vld"    , "dec_ren_int_uop_vld_#{n}_d3"
            signal "rid"    , "dec_ren_int_uop_rid_#{n}_d3", 8
            signal "dst"    , "dec_ren_int_uop_dst_atag_#{n}_d3", 5
            signal "dst_vld", "dec_ren_int_uop_dst_vld_#{n}_d3"
            signal "dstc"   , "dec_ren_int_uop_cc_dst_info_#{n}_d3", 5
            signal "dstc_vld","dec_ren_int_uop_cc_dst_vld_#{n}_d3"
            signal "srcc"   , "dec_ren_int_uop_cc_src_info_#{n}_d3", 5
            signal "srcc_vld","dec_ren_int_uop_cc_src_vld_#{n}_d3"
            1.upto(3) { |m|
              signal "src#{m}", "dec_ren_int_uop_src#{m}_atag_#{n}_d3", 5
              signal "src#{m}_vld", "dec_ren_int_uop_src#{m}_vld_#{n}_d3"
            }
            message { |grp, sigv|
              msg = ""
              msg += "D:R#{sigv[:dst]},"   if sigv[:dst_vld].to_i == 1
              msg += "S1:R#{sigv[:src1]}," if sigv[:src1_vld].to_i == 1
              msg += "S2:R#{sigv[:src2]}," if sigv[:src2_vld].to_i == 1
              msg += "S3:R#{sigv[:src3]}," if sigv[:src3_vld].to_i == 1
              msg += "DC:R#{sigv[:dstc]}," if sigv[:dstc_vld].to_i == 1
              msg += "SC:R#{sigv[:srcc]}," if sigv[:srcc_vld].to_i == 1
              if msg.length == 0
                nil
              else
                grp.short + " atag: " + msg
              end
            }
          }
        }
      }

      block("int_ptag", "u_ooo_dsp.u_ooo_int_dsp") {
        4.times { |n|
          group("uop#{n}", "S1") {
            valid 'vld',  "u_ooo_int_dsp_ctrl.uop_dsp_vld_#{n}_s1"
            signal 'rid', "ooo_iex_issq_packet_#{n}_s1", 7, 0
            signal 'dst',     "ooo_iex_issq_packet_#{n}_s1", 35, 29
            signal 'dst_vld', "ooo_iex_issq_packet_#{n}_s1", 28, 28
            signal 'src1',    "ooo_iex_issq_packet_#{n}_s1", 17, 11
            signal 'src1_vld',"ooo_iex_issq_packet_#{n}_s1", 8, 8
            signal 'src2',    "ooo_iex_issq_packet_#{n}_s1", 27, 21
            signal 'src2_vld',"ooo_iex_issq_packet_#{n}_s1", 18, 18
            signal 'src3',    "ooo_iex_issq_packet_#{n}_s1", 66, 60
            signal 'src3_vld',"ooo_iex_issq_packet_#{n}_s1", 57, 57
            signal 'srcc',    "ooo_iex_issq_packet_#{n}_s1", 42, 38
            signal 'srcc_vld',"ooo_iex_issq_packet_#{n}_s1", 36, 36
            signal 'dstc',    "ooo_iex_issq_packet_#{n}_s1", 50, 46
            signal 'dstc_vld',"ooo_iex_issq_packet_#{n}_s1", 45, 45
            signal 'ls_vld',  "ooo_iex_ls_vld_#{n}_s1"
            message { |grp, sigv|
              msg = ""
              msg += "D:P#{sigv[:dst]},"   if sigv[:dst_vld].to_i == 1
              msg += "S1:P#{sigv[:src1]}," if sigv[:src1_vld].to_i == 1
              msg += "S2:P#{sigv[:src2]}," if sigv[:src2_vld].to_i == 1
              if sigv[:ls_vld].to_i == 1
                msg += "S3:P#{sigv[:src3]}," if sigv[:src3_vld].to_i == 1
              else
                msg += "DC:P#{sigv[:dstc]}," if sigv[:dstc_vld].to_i == 1
              end
              msg += "SC:P#{sigv[:srcc]}," if sigv[:srcc_vld].to_i == 1
              if msg.length == 0
                nil
              else
                grp.short + " ptag: " + msg
              end
            }
          }
        }
      }

      block("disp_to") {
        (1..3).each { |n|
          2.times { |m|
            group("alu#{n}_sel#{m}", "S1") {
              valid  'vld',  "ooo_iex_alu#{n}_vld_#{m}_s1"
              signal 'rid0', "ooo_iex_issq_packet_0_s1", 7, 0
              signal 'rid1', "ooo_iex_issq_packet_1_s1", 7, 0
              signal 'rid2', "ooo_iex_issq_packet_2_s1", 7, 0
              signal 'rid3', "ooo_iex_issq_packet_3_s1", 7, 0
              signal 'sel',  "ooo_iex_alu#{n}_sel_#{m}_s1", 4
              signal 'idx',  "ooo_iex_alu#{n}_wr_idx_#{m}_s1", 12
              message { |grp, sigv|
                uop = sigv[:sel].hex.ffs
                idx = sigv[:idx].hex.ffs
                sigv[:rid] = sigv["rid#{uop}".to_sym]
                "uop%d disp to %s wr_idx=%x" % [uop, grp.short, idx]
              }
            }
          }
        }
        4.times { |n|
          group("lsu_#{n}", "S1") {
            valid  'vld', "ooo_iex_ls_vld_#{n}_s1"
            signal 'idx', "ooo_iex_ls_wr_idx_#{n}_s1", 5
            signal 'rid', "ooo_iex_issq_packet_#{n}_s1", 7, 0
            signal 'lsidx', "ooo_iex_issq_packet_#{n}_s1", 49, 45
            signal 'dst_vld', "ooo_iex_issq_packet_#{n}_s1", 28, 28
            signal 'fp_dst_vld', "ooo_iex_issq_packet_#{n}_s1", 44, 44
            message { |grp, sigv|
              has_dst = sigv[:dst_vld].hex + sigv[:fp_dst_vld].hex
              lsq = has_dst == 0 ? "stq" : "ldq"
              sigv[lsq.to_sym] = sigv[:lsidx]
              "disp to #{grp.short} isq_idx=%{idx}, set #{lsq}=%{lsidx}" % sigv
            }
          }
        }
      }

      block("lsu_pld") {
        4.times { |n|
          group("uop#{n}", "S2") {
            valid  'vld',  "ooo_lsu_uop_vld_#{n}_s2"
            signal 'rid',  "ooo_lsu_uop_rid_#{n}_s2", 8
            signal 'is_fp',"ooo_lsu_uop_is_fp_#{n}_s2"
            signal 'type', "ooo_lsu_uop_type_#{n}_s2", 8
            signal 'size', "ooo_lsu_uop_size_#{n}_s2", 3
            signal 'esize',"ooo_lsu_uop_esize_#{n}_s2", 2
            message "ooo_lsu_uop#{n} type=%{type} esize=%{esize} size=%{size}"
          }
        }
      }

      block("rob", "u_ooo_rob.u_rob_ctrl") {
        4.times { |n|
          group("commit#{n}", "R1") {
            valid  'vld',  "commit_#{n}_r1"
            signal 'rid',  "commit_ptr_#{n}_r1", 8
            message "committed"
          }
        }
      }

      group("bru_flush", "E2") {
        valid  'vld',  "iex_ooo_bru_flush_e2"
        signal 'rid',  "iex_ooo_bru_flush_rid_e2", 8
        message "bru_flush"
      }
      group("all_flush", "R2") {
        valid  'vld',  "ooo_all_flush_r2"
        signal 'rid',  "ooo_all_flush_rid_r2", 8
        message "ooo_flush"
      }

    } # block ooo

    block("iex", "u_oex.u_iex") {
      block("resolve") {
        (1..3).each { |n|
          group("alu#{n}", "E1") {
            valid  'vld', "issq.iex_ooo_alu#{n}_res_vld_e1"
            signal 'rid', "iex_ooo_alu#{n}_res_rid_e1", 8
            message { |grp, sigv| "resolve, " + grp.short }
          }
        }
        group("mdu", "E4") {
          valid  'vld', "mdu.mdu_ctl.mdu_vld_e4"
          signal 'rid', "iex_ooo_mdu_res_rid_e4", 8
          message "resolve, mdu"
        }
      }
      block("int_reg", "regs.iex_int_reg") {
        8.times { |n|
          group("wr#{n}", "En") {
            valid  'vld',   "wr#{n}_vld"
            signal 'iptag', "wr#{n}_src_reg", 7
            signal 'data',  "wr#{n}_data", 64
            message "write int reg P%{iptag} %{data}"
          }
        }
      }
    } # block iex

    block("lsu", "u_lsu") {
      block("resolve", "lsu_frb_ldq_stq_pipe_ctl") {
        group("ld0", "E4") {
          valid  'vld', "lsu_ldq.ldq_resovle_0_e4"
          signal 'rid', "lsu_ldq.ldq_resovle_rid_0_e4", 8
          signal 'status', "lsu_ldq.ldq_resovle_status_0_e4", 3
          message "resolve, ld0 status=%{status}"
        }
        group("ld1", "E4") {
          valid  'vld', "lsu_ldq.ldq_resovle_1_e4" # wrong
          signal 'rid', "lsu_ldq.pipeb_op_rid_e4", 8
          signal 'status', "lsu_ldq.pipeb_ld_status_e4", 3
          message "resolve, ld1 status=%{status}"
        }
        group("st0", "E7") {
          valid  'vld', "lsu_stq.stq_ctrl.resolve_e8_in"
          signal 'rid', "lsu_stq.stq_ctrl.resolve_state_rid_e7", 8
          signal 'status', "lsu_stq.stq_ctrl.resolve_status_e7", 3
          message "resolve, st0 status=%{status}"
        }
      }

      group("get_iex_std0", "E1") {
        valid  'vld', "iex_lsu_istd_dgen0_vld_e1"
        signal 'stq', "iex_lsu_istd_stq0_idx_e1", 5
        signal 'pair',"iex_lsu_istd_stq0_pair_e1"
        signal 'cancel', "iex_lsu_istd_dgen0_cancel_e1"
        signal 'data', "iex_lsu_istd_data0_e1", 64
        message "iex_lsu_std0 data=%{data} cancel=%{cancel} pair=%{pair}"
      }
      group("get_iex_std1", "E1") {
        valid  'vld', "iex_lsu_istd_dgen1_vld_e1"
        signal 'stq', "iex_lsu_istd_stq1_idx_e1", 5
        signal 'cancel', "iex_lsu_istd_dgen1_cancel_e1"
        signal 'data', "iex_lsu_istd_data1_e1", 64
        message "iex_lsu_std0 data=%{data} cancel=%{cancel}"
      }

      ldst = "lsu_frb_ldq_stq_pipe_ctl."
      tlbp = "lsu_pld_pick_tlb.lsu_tlb."
      pickmux = "lsu_pld_pick_tlb.lsu_pick_mux."

      group("pipea_oldest_pick", 'I2') {
        valid  'vld', "#{pickmux}picka_vld_i2"
        signal 'rid', "#{pickmux}picka_rid_i2", 8
        message "pipea_oldest_pick"
      }
      group("pipeb_oldest_pick", 'I2') {
        valid  'vld', "#{pickmux}pickb_vld_i2"
        signal 'rid', "#{pickmux}pickb_rid_i2", 8
        message "pipeb_oldest_pick"
      }

      ['pipea', 'pipeb'].each { |pipe|
        group("#{pipe}_e1", 'E1') {
          valid  'vld', "#{ldst+pipe}_op_vld_e1"
          signal 'rid', "#{ldst+pipe}_op_rid_e1", 8
          signal 'ld_vld', "#{ldst+pipe}_ld_vld_e1"
          signal 'st_vld', "#{ldst+pipe}_st_vld_e1"
          signal 'is_fp',  "#{ldst+pipe}_op_fp_e1"
          signal 'op_idx', "#{ldst+pipe}_op_idx_e1", 5
          signal 'size', "#{ldst+pipe}_op_size_e1", 3
          signal 'va',   "#{tlbp+pipe}_op_va_e1", 64
          message { |grp, sigv|
            lsidx = sigv[:ld_vld].hex == 1 ? 'ldidx=' : 'stidx='
            lsidx += sigv[:op_idx]
            size  = sigv[:size].hex
            if sigv[:is_fp].hex == 1
              bytes = [1,2,4,8,3,6,12,16][size]
            else
              bytes = [1,2,4,8,1,2,12,16][size]
            end
            ("%s %s size=%x(%dB), set va=%s" %
             [grp.short, lsidx, size, bytes, sigv[:va]])
          }
        }
        group("#{pipe}_e3", 'E3') {
          valid  'vld', "#{ldst+pipe}_op_vld_e3"
          signal 'rid', "#{ldst+pipe}_op_rid_e3", 8
          signal 'ld_vld', "#{ldst+pipe}_ld_vld_e3"
          signal 'op_idx', "#{ldst+pipe}_op_idx_e3", 5
          signal 'dc_hit', "#{ldst+pipe}_dc_hit_e3"
          signal 'tlb_hit', "#{ldst+pipe}_tlb_hit_e3"
          signal 'pa',  "#{ldst+pipe}_ipa_pa_e3", 45
          message { |grp, sigv|
            lsidx = sigv[:ld_vld].hex == 1 ? 'ldidx=' : 'stidx='
            lsidx += sigv[:op_idx]
            msg = grp.short + ' ' + lsidx
            msg += ' tlb ' + (sigv[:tlb_hit].hex == 1 ? 'hit,' : 'miss,')
            msg += ' dc ' + (sigv[:dc_hit].hex == 1 ? 'hit,' : 'miss,')
            msg += ' set pa=' + sigv[:pa] if sigv[:tlb_hit].hex == 1
            msg
          }
        }
      } # pipea pipeb

      group("l2c_req", "Q0") {
        unit "L2C"
        valid  'vld', "lsu_ft_mmu_l2c_req_vld_q0"
        signal 'tag', "lsu_ft_mmu_l2c_req_tag_q0", 3
        signal 'type', "lsu_ft_mmu_l2c_req_type_q0", 4
        signal 'matr', "lsu_ft_mmu_l2c_req_matr_q0", 5
        signal 'bm', "lsu_ft_mmu_l2c_req_bm_q0", 16
        signal 'pa', "lsu_ft_mmu_l2c_req_pa_q0", 45
        signal 'op_idx', "lsu_ft_mmu_l2c_req_op_idx_q0", 5
        message "lsu_l2c_req tag=%{tag} idx=%{op_idx} type=%{type} matr=%{matr} bm=%{bm} pa=%{pa}"
      }
      group("l2c_fill_tag", "D1") {
        unit "L2C"
        valid  'vld', "l2c_ft_mmu_lsu_fill_vld_d1"
        signal 'tag', "l2c_ft_mmu_lsu_fill_tag_d1", 3
        message "l2c_lsu_fill tag=%{tag}"
      }

      group("tlb_miss_req", "  ") {
        unit "MMU"
        valid  'vld', "lsu_mmu_tlb_miss_vld"
        signal 'tag', "lsu_mmu_tlb_miss_req_tag", 2
        signal 'va',  "lsu_mmu_tlb_miss_va", 49
        message "lsu_tlb_miss_req tag=%{tag} va=%{va}"
      }
      group("tlb_fill", "  ") {
        unit "MMU"
        valid  'vld', "mmu_lsu_tlb_fill_vld"
        signal 'tag', "mmu_lsu_tlb_fill_req_tag", 2
        signal 'matr',"mmu_lsu_tlb_fill_mem_attr", 8
        signal 'size',"mmu_lsu_tlb_fill_page_size", 8
        signal 'pa',  "lsu_mmu_tlb_miss_va", 44, 12
        signal 'fault',  "mmu_lsu_tlb_fault_vld"
        signal 'syndrom',"mmu_lsu_tlb_fault_syndrom", 6
        message { |grp, sigv|
          msg = "mmu_tlb_fill tag=%{tag} matr=%{matr} size=%{size} pa=%{pa}" % sigv
          if sigv[:fault].hex == 1
            msg += ", fault syndrom=%{syndrom}" % sigv
          end
          msg
        }
      }

    } # block lsu

  end

end
