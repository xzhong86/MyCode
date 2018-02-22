#!/usr/bin/env ruby

require 'optparse'
require 'ostruct'
require 'yaml'

$bin_dir = File.expand_path('..', __FILE__)

load $bin_dir + '/bruce/MultiThread.rb'
load $bin_dir + '/bruce/CASimResult.rb'

# default option value
$options = OpenStruct.new
$options.weight = $bin_dir + '/bruce/spec/weight.csv'
$options.factor = $bin_dir + '/bruce/spec/factor.csv'
$options.inst   = $bin_dir + '/bruce/spec/inst.csv'
$options.freq   = 1000000000


def read_logs (logs)
  tcs = []
  regex = $options.name_regex && Regexp.new($options.name_regex)
  regex ||= $options.glob && Regexp.new($options.glob.sub('*','([\w.-]+)'))
  thnum = $options.thnum || 5
  print "start parsing #{logs.size} logs with #{thnum} threads\n"
  thpool = ThreadPool.new thnum
  logs.each do |log_path|
    if regex && log_path =~ regex
      name = $1
    else
      name = log_path
    end
    res = CASimResult.new name
    tcs << res
    thpool.add_task { res.read_log(log_path) }
  end
  thpool.sync
  return tcs
end

def print_failed (tcs)
  tcs.each do |res|
    next if res.passed?
    cycles = res.data(:cycle) || 0
    insts  = res.data(:inst) || 0
    printf "%-20s %10d cycles, %d insts, %s\n", res.name, cycles, insts, res.reason
  end
end

def print_result (tcs)
  if $options.failed
    return print_failed(tcs)
  end
  tcs.each do |res|
    next if $options.passed and res.failed?
    cycles = res.data(:cycle) || 0
    insts  = res.data(:inst) || 0
    ipc = ''
    res.each_data { |d| ipc += ("%.3f " % (d[:ipc] || 0.0)) }
    printf "%-20s %10d insts, %10d cycles, IPC #{ipc}\n", res.name, insts, cycles
  end
end

def print_spec_report (tcs)
  load $bin_dir + '/bruce/DataTable.rb'
  load $bin_dir + '/bruce/SpecCalc.rb'
  wtab = DataTable.new($options.weight)
  ftab = DataTable.new($options.factor)
  itab = DataTable.new($options.inst  )
  results = tcs.select{ |t| t.passed? }.map{ |t| t.data(0) }
  spec = SpecCalc.new(results, wtab.to_a)
  spec.calculate(itab.to_a, ftab.to_a, $options.freq)
  if $options.verbose
    puts "Passed/Total: #{results.size}/#{tcs.size}"
    puts "Weight: #{$options.weight}"
    puts "Factor: #{$options.factor}"
    puts "Inst: #{$options.inst}"
    printf "Frequency: %.1fGHz\n", $options.freq.to_f / 1000000000
    puts "======== All Subjects ========"
    spec.sub_result.each do |res|
      res[:score] ||= 0.0
      printf("%-24s %d\t%d\t %.3f %.3f\n", res[:sub], res[:inst],
             res[:cycle], res[:ipc], res[:weight])
    end
  end
  puts "======== Major Objects ========"
  printf "%-20s Score  IPC\n", 'Benchmark'
  spec.major_result.each do |res|
    printf "%-20s %6.3f\t %.3f\n", res[:major], res[:score], res[:ipc]
  end
  printf "%-20s %6.3f\t\n", 'FinalScore', spec.final_score
end

def reorganize_logs (logs)
  require 'fileutils'
  regex = $options.name_regex && Regexp.new($options.name_regex)
  regex ||= $options.glob && Regexp.new($options.glob.sub('*','([\w.-]+)'))
  reorg_dir = $options.reorg_dir
  Dir.mkdir reorg_dir if not Dir.exist? reorg_dir
  thnum = $options.thnum || 5
  thpool = ThreadPool.new thnum
  logs.each do |log_path|
    if regex && log_path =~ regex
      name = $1
    else
      name = log_path
    end
    if name =~ /(\w+).(sp\d+)/
      newname = $1 + '_' + $2
      dir = reorg_dir + '/' + $1
    #  thpool.add_task do res.read_log
        Dir.mkdir dir if not Dir.exist? dir
        FileUtils.cp log_path, "#{dir}/#{newname}.log"
    #  end
    else
      puts "Skip: bad name #{name}"
    end
  end
  thpool.sync
end

# main
OptionParser.new do |opts|
  opts.banner = "hasim_result.rb [options] xxx0.log xxx1.log ..."
  opts.on('-t', '--thnum N', 'set thread num')   { |n| $options.thnum = n.to_i }
  opts.on('--glob EXPR', 'use glob to get logs') { |e| $options.glob = e }
  opts.on('--name-regex REGEX', 'set regex to get name from path') { |e| $options.name_regex = e }
  opts.on('--failed', 'print failed cases') { $options.failed = true }
  opts.on('--passed', 'print passed cases') { $options.passed = true }
  opts.on('--save FILE', 'save result in YAML') { |f| $options.save_file = f }
  opts.on('--load FILE', 'load result from YAML') { |f| $options.load_file = f }
  opts.on('--spec-report', 'report for SPEC') { $options.spec_report = true }
  opts.on('--weight CSV', 'set SPEC weight file') { |f| $options.weight = f }
  opts.on('--factor CSV', 'set SPEC factor file') { |f| $options.factor = f }
  opts.on('--spec-inst CSV', 'set SPEC inst file'){ |f| $options.inst = f }
  opts.on('--freq N', 'set simulate Frequency'){ |n| $options.freq = n.to_i }
  opts.on('--reorg DIR', 'reorganize logs') { |d| $options.reorg_dir = d }
  opts.on('-V', '--verbose', 'print more') { $options.verbose = true }
  opts.on_tail('-h', '--help', 'Show help') { puts opts; exit }
end.parse!

logs = nil
logs = Dir.glob($options.glob).sort if $options.glob
logs ||= ARGV if not ARGV.empty?

fail "need log file" if not logs and not $options.load_file

if $options.reorg_dir
  reorganize_logs(logs)
  exit 0
end

if $options.load_file
  tcs = YAML.load(File.open($options.load_file, 'r').read)
else
  tcs = read_logs(logs)
end

if $options.save_file
  File.open($options.save_file, 'w').write(YAML.dump(tcs))
elsif $options.spec_report
  print_spec_report(tcs)
else
  print_result(tcs)
end


