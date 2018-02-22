#!/bin/env perl

use strict;
use FindBin qw($Bin);
use File::Find;

my $root = $Bin;
$root =~ s#/verification/top.*##;
my $top = $root."/verification/top";
my $pre_sim = './pre_sim';

my %option;
my %context;

package TestCase;

sub new {
    my $class = shift;
    my $tc = shift;
    my %args = @_;
    die if ! $tc;
    my $ref = { Name => $tc };
    if ($args{seed} && $args{signature}) {
        my ($seed, $signature) = @args{'seed', 'signature'};
        $ref->{Seeds}[0] = $seed;
        $ref->{Signature} = [ $signature."\n" ];
        $ref->{Signatures}{$seed} = [ $signature."\n" ];
        my $result = $signature =~ /PASSED/ ? "PASSED" : "FAILED";
        $ref->{Result} = $result;
        $ref->{Results}{$seed} = $result;
    }
    $ref->{Option} = $args{option} if ($args{option});
    return bless $ref, $class;
}
sub name { $_[0]->{Name} }
sub option { $_[0]->{Option} }

sub read_tc_log {
    my $log = shift;
    open FILE, "< $log" or die "open failed, $log";
    my @signature;
    my $result;
    my ($pc, $asm, $num);
    while (<FILE>) {
        $pc  = $1 if (/\| RTL\s+PC\s+\|\s+(\S+)/);
        $asm = $1 if (/\| Disassembler\s+\|\s+(.*)/);
        if (/\| Inst Num\s+\|\s+(\S+)/) {
            $num = $1;
            push @signature, "  $num PC=$pc $asm\n";
        }
        if (/TEST\s+(PASSED|FAILED)/ ||
            m/\| ERROR! \|/ ||
            m/\[Monitor\] Test (PASSED|FAILED) :/) {
            push @signature, $_;
            $result = "FAILED" if (/FAILED|ERROR/);
            $result = "PASSED" if (/PASSED/ && !$result);
        }
    }
    close FILE;
    return ($result, \@signature);
}
sub read_log {
    my $self = shift;
    my $tc = $self->name;
    return if $self->{Result};
    # get tc log
    my @logs = glob "$pre_sim/$tc/$tc*.log";
    if (@logs == 0) {
        $self->{Result} = "Never Run";
        return;
    }
    foreach (@logs) {
        my $seed;
        if (/${tc}_(\d+)\.log/) {
            $seed = $1;
        } else {
            next;
        }
        my ($result, $signature) = read_tc_log($_);
        $self->{Result} ||= $result; # equal to last
        $self->{Results}{$seed} = $result;
        $self->{Signature} ||= $signature;
        $self->{Signatures}{$seed} = $signature;
        push @{$self->{Seeds}}, $seed;
    }
}
sub seed  { $_->read_log; $_[0]->{Seeds}[0] }
sub seeds { $_->read_log; @{$_[0]->{Seeds}} }
sub result {
    my ($self, $seed) = @_;
    $self->read_log if ! $self->{Result};
    return $self->{Results}{$seed} if ($seed);
    return $self->{Result};
}
sub is_failed { result(@_) !~ /PASSED/ }
sub is_passed { result(@_) =~ /PASSED/ }
sub signature {
    my ($self, $seed) = @_;
    $self->read_log if ! $self->{Result};
    return @{$self->{Signatures}{$seed}} if ($seed);
    return @{$self->{Signature}};
}

package main;

sub exec_cmd {
    my @cmds = @_;
    push @cmds, " > /dev/null" if $option{"--no-print"};
    my $cmd = join " ", @cmds;
    print "Run: $cmd\n";
    return 0 if $option{"--no-run"};
    return system $cmd;
}

sub find_dir {
    my ($dir, $fname) = @_;
    return "$dir/$fname" if (-f "$dir/$fname");
    foreach (glob "$dir/*") {
        if ( -d $_) {
            my $res = find_dir("$_", $fname);
            return $res if $res;
        }
        if ( -l $_) {
            my $tgt = readlink $_;
            my $res = find_dir($tgt, $fname);
            return $res if $res;
        }
    }
    return undef;
}
sub find_tc_elf_path {
    my $tc = shift;
    return find_dir("$top/tests/AVS_ARCH64", "$tc.ELF");
}

sub read_from_list_file {
    my @flist = @_;
    my $succ;
    foreach (@flist) {
        $succ = open FILE, "< $_";
        last if $succ;
    }
    die "Can't open any of list: " . join(",",@flist)
        if (! $succ);
    my @list;
    while (<FILE>) {
        chomp; s/#.*//; s/^\s+//; s/\s+$//; s/\s+/ /g;
        next if (! $_);
        if (/([\w.]+)(\s+)?(.*)?/) {
            if ($option{"--check-tc"}) {
                my $path = find_tc_elf_path($1);
                die "tc $1 not found" if (!$path);
            }
            push @list, [$1, $3] if $2;
            push @list, $1 if ! $2;
        } else {
            die "Bad tc line $_";
        }
    }
    close FILE;
    return @list;
}

sub read_from_grep_list {
    my $fname = shift;
    open FILE, "< $fname" or die "open $fname failed";
    my @tcs;
    while (<FILE>) {
        chomp; s/#.*//; s/^\s+//;
        next if (! $_);
        if (/([\w-.]+)\/\1_(\d+)\.log(:\d+)?:(.*)/) {
            my $tc = TestCase->new($1, seed => $2, signature => $4);
            push @tcs, $tc;
        } else {
            die "Bad grep line $_";
        }
    }
    close FILE;
    return @tcs;
}

sub get_all_tcs {
    my @dirs = glob "$pre_sim/*";
    my @tcs;
    foreach (@dirs) {
        next if ! -d $_;
        foreach (glob "$_/*.log") {
            if (/([\w-.]+)\/\1_(\d+)\.log/) {
                push @tcs, $1;
                last;
            }
        }
    }
    print "No TC found\n" if (@tcs == 0);
    return @tcs;
}

sub get_tc_list {
    my (@list, @TCS);
    if ($option{"--list"}) {
        @list = read_from_list_file($option{"--list"});
    }
    elsif ($option{"--grep-list"}) {
        @TCS = read_from_grep_list($option{"--grep-list"});
    }
    else {
        @list = get_all_tcs();
    }
    if (! $option{"--grep-list"}) {
        @TCS = map {
            if (ref $_) {
                TestCase->new($$_[0], option => $$_[1]);
            } else {
                TestCase->new($_);
            }
        } @list;
    }
    my $match = $option{"--match"};
    @TCS = grep { $_->name =~ /$match/ } @TCS if $match;
    @TCS = grep { $_->is_failed } @TCS if $option{"--failed"};
    @TCS = grep { $_->is_passed } @TCS if $option{"--passed"};
    @TCS = sort { $a->name cmp $b->name } @TCS if $option{"--sorted"};
    $context{TCS} = \@TCS;
}

# --list, --match, --no-run, --no-print
# --dump, --thread, --Monitor_dump_commit
sub cmd_run {
    my $args = shift;
    my $tc = shift @$args;
    my @tclist;
    if ($tc =~ ".*\.list") {
        $option{"--list"} ||= $tc;
    }
    else {
        $option{"--match"} ||= $tc;
    }
    get_tc_list();
    my @TCS = @{$context{TCS}};
    printf "prepare to run %d tests\n", scalar(@TCS);
    my @runcmd = qw/make batch_run/;
    push @runcmd, "dump=on" if $option{"--dump"};
    push @runcmd, "udr=\"+Monitor_dump_commit\""
        if $option{"--Monitor_dump_commit"};
    if ($option{"--thread"} && $option{"--thread"} > 1) {
        require threads or die;
        require Thread::Semaphore or die;
        my $thread_num = $option{"--thread"};
        my $semaphore = Thread::Semaphore->new($thread_num);
        foreach (@TCS) {
            $semaphore->down(1);
            my @cmd = @runcmd;
            push @cmd, 'tc=' . $_->name;
            push @cmd, 'tc_mode=elf64' if $_->option !~ /tc_mode=/;
            push @cmd, $_->option if $_->option;
            threads->new(sub {
                exec_cmd @cmd, "tc=".$_->name;
                $semaphore->up(1);
                         }
                )->detach();
        }
        $semaphore->down($thread_num);
    } else {
        foreach (@TCS) {
            my @cmd = @runcmd;
            push @cmd, 'tc=' . $_->name;
            push @cmd, 'tc_mode=elf64' if $_->option !~ /tc_mode=/;
            push @cmd, $_->option if $_->option;
            exec_cmd @cmd;
        }
    }
}


sub get_signature_feature {
    my $tc = shift;
    return "PASSED" if $_->is_passed;
    foreach ($tc->signature) {
        return "NoCommit" if (/No instruction committed/);
        return "ESR..." if (/ESR_EL\d/);
        return "FAR..." if (/FAR_EL\d/);
    }
    return "FAILED";
}

sub cmd_print {
    my $args = shift;
    my $act = shift @$args;
    if ($act =~ /result|signature|name/) {
        my $list = shift @$args;
        $option{"--list"} ||= $list;
    }
    get_tc_list();
    my @TCS = @{$context{TCS}};
    if ($act eq "signature") {
        foreach (@TCS) {
            print "-" x 80, "\n";
            print $_->name, " seed=", $_->seed, "\n";
            print foreach ($_->signature);
        }
    }
    if ($act eq "result") {
        foreach (@TCS) {
            my $name = $_->name;
            my $feat = get_signature_feature($_);
            printf "%-48s %s\n",$name,$feat;
        }
    }
    if ($act eq "name") {
        foreach (@TCS) {
            print $_->name, "\n";
        }
    }
}


# report avs // report avs test result
sub get_avs_short_name {
    my $n = shift;
    return $n if $option{"--no-short"};
    if ($n =~ /(\w+).int_test_start_(el\dn?s?).int_(\d+k).int_config_mmu_on/) {
        return "$1.$2.$3";
    }
    return $n;
}
sub get_mon_avs_result {
    my $log = shift;
    open FILE, "< $log" or die "open failed, $log";
    my ($cmt, $res);
    while (<FILE>) {
        if (/\[AVS_TUBE\].*: \*\* TEST (.*) \*\*/) {
            my $stat = $1;
            if ($stat =~ /COMPLETE|FAILED|PASSED|SKIPPED/) {
                $res = $stat;
            }
        }
        if (/^Commit (\d+) @ \d+,/) {
            $cmt = $1;
        }
    }
    close FILE;
    return ($cmt, $res);
}

sub cmd_report {
    my $args = shift;
    my $act = shift @$args;
    if ($act eq "avs") {
        my ($total, $passed);
        print "AVS TC result report\n";
        foreach (glob "$pre_sim/*") {
            next if ! -d $_;
            next if ! -f "$_/core0_mon.log";
            if (/pre_sim\/(\S+)/) {
                my $name = get_avs_short_name($1);
                my ($cmt, $res) = get_mon_avs_result("$_/core0_mon.log");
                printf "%-63s %.1fk\t %s\n",$name,$cmt/1000,$res;
                $total ++;
                $passed ++ if $res =~ /PASSED/;
            }
        }
        print "Total $total, Passed $passed\n";
    }
}

# svn info
# svn up all/rtl/bin/top/common
sub cmd_svn {
    my $args = shift;
    my $act = shift @$args;
    my %dirs = ( rtl => "rtl", bin => "bin", top => "verification/top",
                 common => "verification/common" );

    if ($act eq "info") {
        foreach (values %dirs) {
            my $res = join "",`svn info $root/$_`;
            if ($res =~ /Revision: (\d+)/) {
                print "$1 \t$_\n";
            } else {
                die "Bad svn info"
            }
        }
        return;
    }
    if ($act eq "up") {
        my $dir = shift @$args;
        my @list;
        $list[0] = $dirs{$dir};
        @list = values %dirs if ($dir eq "all");
        die "Bad svn up target: $dir" if (!defined $list[0]);
        foreach (@list) {
            exec_cmd "svn up $root/$_";
        }
    }
}

my @options = (
    'run' => {
        Action => \&cmd_run,
        Arg => "TCExpr,regress",
        Explain => "Run special test cases",
    },
    'report' => {
        Action => \&cmd_report,
        Arg => "avs",
        Explain => "report result of test cases",
    },
    'print' => {
        Action => \&cmd_print,
        Arg => "signature [list]",
        Explain => "print result of test cases",
    },
    'svn' => {
        Action => \&cmd_svn,
        Arg => "up/info",
        Explain => "svn cmd for rtl/bin/top/common",
    },
    );

use File::Basename;
use List::Util qw (reduce);

sub print_help {
    my $myname = basename $0;
    my %opthash = @options;
    my @optlist = grep { !ref } @options;
    print "$myname (",join('|',@optlist),")+\n";
    print "TCExpr: test case express, it simplely replace * with .*\n";
    print "        ooo*mov match testcases contain ooo and mov\n";
    print "        ^ooo* match testcase head with ooo\n";
    print "        *mov\$ match testcase end with mov\n";
    print "        1_mov match testcase contain 1_mov\n";
    print "Options:\n";
    print "  --no-run  don't run the command, only print\n";
    print "Actions:\n";
    my $longest_opt = length (
        reduce { length($a) > length($b)? $a: $b } @optlist );
    my $longest_arg = length (
        reduce { length($a) > length($b)? $a: $b } (
            map { $$_{Arg} } values %opthash) );
    foreach (@optlist) {
        my $opt = $opthash{$_};
        printf("  %-*s%-*s%s\n",$longest_opt+1,$_,
               $longest_arg+1,$$opt{Arg}, $$opt{Explain});
    }
}

sub main {
    my @argv = @_;
    my %opthash = @options;
    if (@argv == 0) {
        print_help();
        exit 1;
    }
    foreach (@argv) { # get options
        if (/^(--[\w-]+)(=)?(.*)?/) {
            $option{$1} = defined $2 ? $3 : 1;
        }
    }
    $pre_sim = $option{"--sim"} . '/pre_sim' if $option{"--sim"};
    @argv = grep { !/^--/ } @argv;
    while ($_ = shift @argv) {
        my $opt = $opthash{$_};
        if ($opt) {
            $opt->{Action}(\@argv);
        } else {
            print STDERR "Bad option $_\n" if ($_ ne "help");
            print_help();
            exit 1;
        }
    }
}

&main(@ARGV);
