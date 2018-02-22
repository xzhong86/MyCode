#!/usr/bin/perl
# zhongzhiping z00249865, diagnose test failure feature

use strict;
use threads;
use Thread::Queue;

my %options;
my $thread_num = 30;  # default thread num
my $csv_file = 'diagnose_report.csv';  # default csv file
my $pre_sim = './pre_sim';

package ChkBase;
sub new { bless { name => $_[0] }, $_[0] }
sub name { $_[0]->{name} }
sub brief { $_[0]->{brief} }
sub detail { $_[0]->{detail} }
sub start_check { return }
sub check_line { return }
sub commit { return }
sub commit_dump { return } 
sub flush_dump { return } 
sub hangup_dump { return } 
sub end_check { return }


package ChkCrossPage;
our @ISA = 'ChkBase';
use Math::BigInt;
sub new { return bless { LINES => [] }, $_[0]; }
sub _unused_check_line {
    my ($self, $lno, $line) = @_;
    return if @{$self->{LINES}} >= 3;
    if ($line =~ /E1 op[01] (load|store) is CrossPage/) { # new way
        push @{$self->{LINES}}, $lno;
    }
    if ($line =~ /E1 pipe.*ma2, set va=([\da-f]+)/) {
        my $va = Math::BigInt->new('0x'.$1);
        if (($va % 4096) < 16) {
            push @{$self->{LINES}}, $lno;
        }
    }
}
sub check_cnc_crosspage {
    my @msgs = @_;
    for (my $i = 0; $i < @msgs - 1; $i ++) {
        if ($msgs[$i] =~ /E3 pipea tlb hit,( nc,)?/) {
            my $nc1 = $1 ? $1 : "";
            if ($msgs[$i+1] =~ /E3 pipea tlb hit,( nc,)?/) {
                my $nc2 = $1 ? $1 : "";
                if ($nc1 ne $nc2) {
                    return "CrossPageCNC"
                }
            }
        }
    }
    return undef;
}
sub check_dump {
    my ($self, $dmp) = @_;
    return if $self->{brief};
    my $inst = hex($dmp->{INST});
    return if $inst & 0x0a00_0000 != 0x0800_0000; # not load or store
    my $crosspage = grep /E1 .* CrossPage/, @{$dmp->{MSGS}};
    return if ! $crosspage;
    $self->{brief} = "CrossPage";
    my @pipea = grep /E[13] pipea/, @{$dmp->{MSGS}};
    my @pipeb = grep /E[13] pipeb/, @{$dmp->{MSGS}};
    my $res = check_cnc_crosspage(@pipea);
    $res = check_cnc_crosspage(@pipeb) if ! $res;
    $self->{brief} = "CrossPageCNC" if $res;
}
sub commit_dump { check_dump(@_) }
sub hangup_dump { check_dump(@_) }
sub end_check {
    my ($self, $signature) = @_;
    if ($self->{brief}) {
        $self->{detail} = $self->{brief};
    }
}


package ChkBarrier;
our @ISA = 'ChkBase';
sub commit {
    my ($self, $cmt) = @_;
    my $inst = hex($cmt->{CODE});
    my $barr;
    $barr = 'DMB' if (($inst & 0xffff_f0ff) == 0xd503_30bf);
    $barr = 'DSB' if (($inst & 0xffff_f0ff) == 0xd503_309f);
    $barr = 'Release' if (($inst & 0x3f40_8000) == 0x0800_8000);
    #$barr = 'Acquire' if (($inst & 0x3f40_8000) == 0x0840_8000);
    if ($barr) {
        $self->{BARRIER}{$barr} ++;
        $self->{LAST} = $barr;
    }
}
sub end_check {
    my ($self, $signature) = @_;
    my $nocommit = grep { /No instruction committed/ } @$signature;
    if ($self->{LAST}) {
        $self->{brief} = "NoCmtBarrier" if $nocommit;
        $self->{detail} = join ':', keys %{$self->{BARRIER}};
    }
}


package ChkDCOperation;
our @ISA = 'ChkBase';
sub commit {
    my ($self, $cmt) = @_;
    my $inst = hex($cmt->{CODE});
    my $dc;
    $dc = 'DCIVAC' if (($inst & 0xffff_ffe0) == 0xd508_7620);
    $dc = 'DCISW'  if (($inst & 0xffff_ffe0) == 0xd508_7640);
    $dc = 'DCZVA'  if (($inst & 0xffff_ffe0) == 0xd50b_7420);
    if ($dc) {
        $self->{DC}{$dc} ++;
        $self->{HAS_DCI} = 1 if $dc =~ /^DCI/;
        $self->{HAS_DCZ} = 1 if $dc =~ /^DCZ/;
    }
}
sub end_check {
    my ($self, $signature) = @_;
    my $regerr = grep { /\| ERROR! \| (X\d+|V\d+)/ } @$signature;
    $self->{detail} = join ':', keys %{$self->{DC}};
    if ($regerr && $self->{HAS_DCI}) {
        $self->{brief} = "DCInvalid";
        return;
    }
    return if ! $self->{HAS_DCZ};
    foreach (@$signature) {
        if (/\| ERROR! \| (X\d+|V\d+)\s+\| (\w+) \| (\w+) \| (\w+)/) {
            my ($reg, $aem, $rtl, $old) = ($1, $2, $3);
            if ($aem == 0 && $rtl !~ /^0+$/ && $aem ne $old) {
                $self->{brief} = "DCZVA";
                return;
            }
        }
    }
}


package ChkSIMDMismatch;
our @ISA = 'ChkBase';
sub commit {
    my ($self, $cmt) = @_;
    my $inst = hex($cmt->{CODE});
    if (($inst & 0x0e00_0000) == 0x0e00_0000) {
        # Data Processing, Float and SIMD
        $self->{LAST_SIMD} = $cmt->{TIME};
        $self->{LAST_SIMD_CODE} = $cmt->{CODE};
    }
}
sub end_check {
    my ($self, $signature) = @_;
    my ($excp, $vreg, $commit_r4);
    foreach (@$signature) {
        if (!$commit_r4 && m/\| Timestamp .*\| (\d+)/) {
            $commit_r4 = $1;
        }
        if (/\| ERROR! \| (X\d+|V\d+|FPSR)/) {
            $vreg .= $1 . ' ';
        }
        if (/(ESR|FAR|ELR)_EL/) {
            $excp = 1;
        }
    }
    my $last_simd = $self->{LAST_SIMD};
    if (!$excp && $vreg && $last_simd && $commit_r4 - $last_simd < 30) {
        $self->{brief} = "SIMDDPMismatch";
        $self->{detail} = $vreg . $self->{LAST_SIMD_CODE};
    }
}


package ChkFPLDFARMis;
our @ISA = 'ChkBase';
sub check_line {
    my ($self, $lno, $line) = @_;
    if ($line =~ /^Dump \d+, Rid [\da-f]+,/) {
        $self->{fpldst_uop} = 0;
        $self->{fpload_multi_uop} = undef;
    }
    if ($line =~ /S2 ooo_lsu_uop type=[\da-f]+\((LOAD|STORE)\(FP\)\)/) {
        $self->{fpldst_uop} ++;
        if ($self->{fpldst_uop} == 2) {
            $self->{fpload_multi_uop} = $lno;
        }
    }
}
sub end_check {
    my ($self, $signature) = @_;
    my $far = grep /FAR_EL/, @$signature;
    if ($far && $self->{fpload_multi_uop}) {
        $self->{brief} = "FPFARMis";
        $self->{detail} = $self->{fpload_multi_uop};
    }
}


package ChkSTXMismatch;
our @ISA = 'ChkBase';
sub end_check {
    my ($self, $signature) = @_;
    my ($stx, $stxmis);
    foreach (@$signature) {
        if (/\| Disassembler\s+\| (STL?X[PR]\w*)/) {
            $stx = $1;
        }
        if ($stx && m/\| ERROR! \| X\d+\s+\| ([\da-f]+) \| ([\da-f]+)/) {
            my ($aem, $rtl) = (hex($1), hex($2));
            if ($stx && ($aem == 0 || $aem == 1) && ($rtl == 0 || $rtl == 1)) {
                $stxmis = 1;
            }
        }
    }
    if ($stxmis) {
        $self->{brief} = "STXMismatch";
        $self->{detail} = $stx;
    }
}


package ChkBigEndian;
our @ISA = 'ChkBase';
sub reverse_ext {
    my ($val, $size, $sext) = @_;
    my $hexlen = $size * 2;
    my $len = length $val;
    my $tmp = substr $val, $len - $hexlen, $hexlen;
    my $rev = join('',reverse(split(/(\w\w)/,$tmp)));
    return $rev if $len <= $hexlen;
    if ($sext == 0) {
        return "0" x ($len - $hexlen) . $rev;
    } else {
        $sext = $sext * 2;
        my $ext;
        $ext = "f" x ($sext - $hexlen) if $rev =~ /^[89a-f]/;
        $ext = "0" x ($sext - $hexlen) if $rev =~ /^[0-7]/;
        return "0" x ($len - $sext) . $ext . $rev;
    }
}
sub end_check {
    my ($self, $signature) = @_;
    my $bigend;
    foreach (@$signature) {
        if (/\| ERROR! \| ([XV])\d+\s+\| ([\da-f]+) \| ([\da-f]+)/) {
            my ($xv, $aem, $rtl) = ($1, $2, $3);
            if ($aem eq reverse_ext($rtl, length($rtl) / 2)) {
                $bigend = 1;
                last;
            }
            if ($xv eq 'X' && $aem =~ /^(00000000|ffffffff)/ &&
                (($aem eq reverse_ext($rtl, 4, 0) && $rtl eq reverse_ext($aem, 4, 0)) ||
                 ($aem eq reverse_ext($rtl, 2, 0) && $rtl eq reverse_ext($aem, 2, 0)) ||
                 ($aem eq reverse_ext($rtl, 4, 8) && $rtl eq reverse_ext($aem, 4, 8)) ||
                 ($aem eq reverse_ext($rtl, 2, 8) && $rtl eq reverse_ext($aem, 2, 8)) ||
                 ($aem eq reverse_ext($rtl, 2, 4) && $rtl eq reverse_ext($aem, 2, 4)))) {
                $bigend = 1;
                last;
            }
            if ($xv eq 'V' && $aem =~ /^(00000000|ffffffff)/ &&
                (($aem eq reverse_ext($rtl, 8, 0) && $rtl eq reverse_ext($aem, 8, 0)) ||
                 ($aem eq reverse_ext($rtl, 4, 0) && $rtl eq reverse_ext($aem, 4, 0)) ||
                 ($aem eq reverse_ext($rtl, 2, 0) && $rtl eq reverse_ext($aem, 2, 0)) )) {
                $bigend = 1;
                last;
            }
        }
    }
    if ($bigend) {
        $self->{brief} = "BigEndian";
        $self->{detail} = "BigEndian";
    }
}


package ChkBadELF;
our @ISA = 'ChkBase';
sub check_line {
    my ($self, $lno, $line) = @_;
    $self->{Commit} ++ if $line =~ /^Commit/;
    $self->{FlushZero} ++ if $line =~ /^Flush \(ooo\) 0 ->/;
}
sub end_check {
    my ($self, $signature) = @_;
    if (! $self->{Commit} && $self->{FlushZero} > 3) {
        $self->{brief} = "BadELF";
        $self->{detail} = "BadELF";
    }
}


package ChkInstHLT; # HLT not supported now
our @ISA = 'ChkBase';
sub flush_dump {
    my ($self, $dmp) = @_;
    my $masked = hex($dmp->{INST}) & 0xffe0_001f; # exception inst mask
    my $einst;
    $einst = 'HLT' if $masked == 0xd440_0000;
    $einst = 'BRK' if $masked == 0xd420_0000;
    $einst = 'DCPS1' if $masked == 0xd4a0_0001;
    $einst = 'DCPS2' if $masked == 0xd4a0_0002;
    $einst = 'DCPS3' if $masked == 0xd4a0_0003;
    if ($einst) {
        $self->{brief} = $einst;
        $self->{detail} = $einst . 'notSupport';
    }
}


package ChkExpLock;
our @ISA = 'ChkBase';
sub hangup_dump {
    my ($self, $dmp) = @_;
    return if $self->{brief};
    my ($max, $cnt, $prev) = (0, 0, 0);
    my ($tlb_req, $tlb_req_cnt) = (0, 0);
    foreach (@{$dmp->{MSGS}}) {
        if (/^\s+(\d+)\s+E3 pipe[ab].*tlb miss/) {
            my $time = int($1);
            if ($prev > 0) {
                $max = $time - $prev if $time - $prev > $max;
                $cnt += 1;
                $prev = $time;
            } else {
                $prev = $time;
            }
        }
        if (/lsu_mmu_tlb_miss/) {
            $tlb_req = 1;
            $tlb_req_cnt ++;
        }
        if (/mmu_lsu_tlb_fill/) {
            $tlb_req = 0;
        }
        if (/^\s+(\d+)\s+dump/) {
            my $time = int($1);
            if (($cnt > 5 && $time - $prev < $max) ||
                ($cnt > 9 && $tlb_req == 1 && $tlb_req_cnt < 3) ) {
                $self->{brief} = 'ExpLock';
                $self->{detail} = 'ExpLiveLock';
            }
        }
    }
}


package main;

sub get_feature {
    my $signature = shift;
    my $feat;
    foreach (@$signature) {
        if (/\| ERROR! \| (\S+)/) {
            $feat .= $1 . ' ';
        }
        if (/No instruction committed/) {
            $feat .= 'NoCommit';
        }
    }
    $feat =~ s/\s*$//;
    return $feat;
}

sub callback_dump {
    my ($stat, $dmp, $chks) = @_;
    return if $dmp->{DUMPPED} || ! defined $dmp->{INST};
    if ($stat eq 'commit') {
        $_->commit_dump($dmp) foreach @$chks;
    }
    elsif ($stat eq 'flush') {
        $_->flush_dump($dmp) foreach @$chks;
    }
    elsif ($stat eq 'hangup' && $dmp->{NO} == 0) {
        $_->hangup_dump($dmp) foreach @$chks;
    }
    $dmp->{DUMPPED} = 1;
}

sub diagnose_tc {
    my ($signature, $log) = @_;
    if (! open FILE, "< $log") {
        print STDERR "open $log failed\n";
        return ('Unknown', 'CantOpenLog');
    }

    my @checkers;
    push @checkers, ChkCrossPage->new;
    #push @checkers, ChkBarrier->new;
    push @checkers, ChkSIMDMismatch->new;
    push @checkers, ChkFPLDFARMis->new;
    push @checkers, ChkDCOperation->new;
    push @checkers, ChkSTXMismatch->new;
    push @checkers, ChkBigEndian->new;
    push @checkers, ChkBadELF->new;
    push @checkers, ChkInstHLT->new;
    push @checkers, ChkExpLock->new;

    my $line_no;
    my %cur_dump;
    my $cur_stat;
    while (my $line = <FILE>) {
        $line_no ++;
        $_->check_line($line_no, $line) foreach @checkers;
        if ($line =~ /^Commit (\d+) @ (\d+), ([\da-f]+) ([\da-f]+) ([\da-f]+), cost (\d+)/) {
            my $cmt = { NO => $1, TIME => $2, RID => $3, PC => $4,
                        CODE => $5, COST => $6 };
            $_->commit($cmt) foreach @checkers;
            $cur_stat = 'commit';
        }
        elsif ($line =~ /^Flush /) {
            $cur_stat = 'flush';
        }
        elsif ($line =~ /Core\d+ Dead Dump/) {
            $cur_stat = 'hangup';
        }

        if ($line =~ /^Dump (\d+), Rid ([\da-f]+), PC ([\da-f]+), INST ([\da-f]+)/) {
            callback_dump($cur_stat, \%cur_dump, \@checkers);
            %cur_dump = ( NO => $1, RID => $2, PC => $3, INST => $4, MSGS => [] );
        }
        elsif ($line =~ /^\s+\d+\s+\S+/) {
            push @{$cur_dump{MSGS}}, $line;
        }
        else {
            callback_dump($cur_stat, \%cur_dump, \@checkers);
        }
    }
    callback_dump($cur_stat, \%cur_dump, \@checkers);
    close FILE;

    my (@briefs, @details);
    foreach (@checkers) {
        $_->end_check($signature);
        push @briefs, $_->brief if $_->brief;
        push @details, $_->detail if $_->detail;
    }
    my $brief = join ':', @briefs;
    my $detail = join ':', @details;
    if (@briefs == 0) {
        $brief = 'Unknown';
        my $feat = get_feature($signature);
        $detail = $detail ? "$detail $feat" : $feat;
    }
    return ($brief, $detail);
}

sub read_tc_log {
    my $log = shift;
    open FILE, "< $log" or die "open failed, $log";
    my @signature;
    my $result;
    while (<FILE>) {
        if (/TEST\s+(PASSED|FAILED)/ ||
            m/\| ERROR! \|/ ||
            m/\[Monitor\] Test (PASSED|FAILED) :/) {
            push @signature, $_;
            $result = "FAILED" if (/FAILED|ERROR/);
            $result = "PASSED" if (/PASSED/ && $result ne 'FAILED');
        }
        elsif (/^\| (Timestamp|RTL PC|Disassembler|Inst Code|Inst Num).*\|/) {
            push @signature, $_;
        }
    }
    close FILE;
    return ($result, \@signature);
}

sub parse_one {
    my $log = shift;
    my ($tc, $seed);
    if ($log =~ /([\w-.]+)\/\1_(\d+)\.log/) {
        ($tc, $seed) = ($1, $2);
    } else {
        print STDERR "Bad log file $log\n";
        return;
    }
    my ($result, $signature) = read_tc_log($log);
    return ($tc, $seed, $result) if $result eq 'PASSED';

    my ($brief, $detail) = diagnose_tc($signature,
                                       "$pre_sim/$tc/core0_mon_$seed.log");
    return ($tc, $seed, $result, $brief, $detail);
}

sub parser {
    my ($log_queue, $res_queue) = @_;
    while (1) {
        my $log = $log_queue->dequeue;
        last if $log eq 'END';
        my @res : shared;
        @res = parse_one($log);
        $res_queue->enqueue(\@res) if @res;
    }
}

sub print_result {
    my $queue = shift;
    open CSV, "> $csv_file" or die "open $csv_file failed";
    while (1) {
        my $res = $queue->dequeue;
        last if ! ref $res && $res eq 'END';
        my ($tc, $seed, $result, $brief) = @$res;
        if ($result eq 'PASSED') {
            printf "%-40s  $result\n", $tc;
        } else {
            printf "%-40s  $result $brief\n", $tc;
        }
        print CSV join(',', @$res),"\n";
    }
    close CSV;
}

sub finder {
    my $queue = shift;
    my $list = $options{"--list"};
    if ($list) { # read from list file
        open FILE, "< $list" or die "open $list failed";
        while (<FILE>) {
            chomp; s/#.*//; s/^\s+//; s/\s+$//; s/\s+/ /g;
            if (/([\w.]+)/) {
                my $tc = $1;
                my @logs = glob "$pre_sim/$tc/$tc*.log";
                next if @logs == 0;
                $queue->enqueue(@logs);
            }
        }
        close FILE;
    } else {
        opendir DIR, "$pre_sim" or die "open $pre_sim failed";
        while ($_ = readdir DIR) {
            next if /^\./;
            my $tc = $_;
            my @logs = glob "$pre_sim/$tc/$tc*.log";
            next if @logs == 0;
            $queue->enqueue(@logs);
        }
        closedir DIR;
    }
}

sub parse_logs {
    my $log_queue = Thread::Queue->new;
    my $res_queue = Thread::Queue->new;
    my $finder = threads->create(\&finder, $log_queue);
    my $printer = threads->create(\&print_result, $res_queue);

    my @parsers;
    push @parsers, threads->create(\&parser, $log_queue, $res_queue)
        foreach (1 .. $thread_num);

    $finder->join;
    $log_queue->enqueue('END') foreach (1 .. $thread_num);

    $_->join foreach (@parsers);

    $res_queue->enqueue('END');
    $printer->join;
}

sub main {
    $options{"--list"} = $ARGV[0] if ($ARGV[0] =~ /.*\.list/);
    foreach (@ARGV) {
        if (/^(--[\w-]+)(=)?(.*)?/) {
            $options{$1} = defined $2 ? $3 : 1;
        }
    }
    $thread_num = $options{"--thread"} if $options{"--thread"};
    $csv_file = $options{"--csv"} if $options{"--csv"};
    $pre_sim = $options{"--pre_sim"} if $options{"--pre_sim"};
    $pre_sim = $options{"--sim"} . '/pre_sim' if $options{"--sim"};
    $pre_sim =~ s#//#/#;
    $pre_sim =~ s#/$##;
    parse_logs();
}

&main;
