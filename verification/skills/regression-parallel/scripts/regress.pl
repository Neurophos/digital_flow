#!/projects/shared/perl-latest/bin/perl -w

use strict;
use Cwd;
use FileHandle;
use File::Basename;
use File::Copy;
use POSIX qw( ceil );
use Data::Dumper;


################################################################################
# Setup paths

my $DEFAULT_JOB_QUEUE = "short";
my $DEFAULT_JOB_PRIORITY = -1000;
my $DEFAULT_JOB_TYPE = "batch";
my $LSF_SUBMIT = "lsf-submit";
my $emailDomain = "neurophos.com";


################################################################################
# Script setup

my $CWD = cwd;
my $scriptDir = dirname($0);
my $script = basename($0,".pl");
my $realScript = basename($0);
my $lastDir = basename($CWD);
chomp($lastDir);


my $pollResultOnly = $ENV{POLL_RESULT_ONLY};
if ($pollResultOnly) {
   $script .= ".poll";
}

################################################################################
# Normal start

my $startTime = time();
my $dateStamp = `date`; chomp($dateStamp);
my $hostStamp = `uname -n -p -o -r`; chomp($hostStamp);
open(STDERR,">&STDOUT");
select(STDOUT); $| = 1;
my $logFile = ".regress_output.log";
system("rm -f $logFile");
open(STDOUT, "| tee -ai $logFile");

################################################################################
# Debug flags


################################################################################
# subs

sub usage();
sub readTestList($);
sub runTests(\@);
sub runTest($);
sub getTestResult($);
sub getTestsResult(\@);
sub getTimeString($);
sub updateTestsResult($$);
sub stringTestsResult($$$@);
sub getRegressHeader();
sub delEnvVars();
sub numJobsFinished(\@);
sub fail($);
sub finish($$);

################################################################################
# Parse arguments

my $all = 0; # find and run all the regr/rel_regress.list
my $ws_dir = "";
my $testList;
my $cppOpts = "";
my $queue = "";
my $licenses = "";
my $resources = "";
my $global_nbads   = 0;
my $global_unknown = 0;
my $quiet=0;
my $use_lsf = 1; # default is LSF 
my $na = "-";

while (scalar(@ARGV)) {
   my $arg = shift @ARGV;
   if ($arg eq '--help' || $arg eq '-h') {
      usage();
   } elsif ($arg eq '--all') {
      $all = 1;
   } elsif ($arg eq '--ws_dir') {
      $ws_dir = shift @ARGV;
   } elsif ($arg eq '--testlist') {
      $testList = shift @ARGV;
      if (!defined $testList || !-f $testList || !-r $testList) {
         warn "$script: testlist [$testList] undefined or not readable.\n";
      }
   } elsif ($arg eq '--cppopts') {
      $cppOpts = shift @ARGV;
   } elsif ($arg eq '--licenses') {
      $licenses = shift @ARGV;
   } elsif ($arg eq '--resources') {
      $resources = shift @ARGV;
   } elsif ($arg eq '--queue') {
      $queue = shift @ARGV;
   } elsif ($arg eq '--lsf') {
      $use_lsf = 1;
   } elsif ($arg eq '--age') {
      $use_lsf = 0;
   } elsif ($arg eq '--quiet' || $arg eq '-q') {
      $quiet = 1;
   }
}

if (!defined $testList) {
   die "$script: must specify testlist.\nTry '$script --help' for help.\n";
}



################################################################################
# Test's status types

my $TEST_PASSED     = "passed";
my $TEST_FAILED     = "failed";
my $TEST_KILLED     = "killed";
my $TEST_NOTFOUND   = "notfnd";
my $TEST_UNKNOWN    = "unknwn";
my $TEST_COMPERR    = "cmperr";
my $TEST_QUEUED    = "queued";
my $TEST_RUNNING    = "running";
my $TEST_FINISHED   = "finished";
my $TEST_SUSPENDED  = "suspended";

my $jobQueue = $ENV{JOB_QUEUE}? $ENV{JOB_QUEUE} : $queue ? $queue : $DEFAULT_JOB_QUEUE;
my $user = qx(whoami); chomp $user;
my $date = qx(date +"%D"); chomp $date;
my $regressionId = "$script-${user}-$date-$$";
$regressionId =~ s:/:_:g;

################################################################################
# body


my @results = ();
my %cmd_map;
my %list_map = ();
my $test_cnt = 1;
my ($resultListing, $nbads, $unknown);
my $create_screenshot=0;
my $MAKE = "make --no-print-directory";

if($ws_dir eq "") {
   $ws_dir = `pi ws st | egrep Directory | cut -d ":" -f 2`; chomp($ws_dir);
   $ws_dir =~ s/^\s+//;
}
print "Workspace Directory: $ws_dir\n";

delEnvVars();

my @testList = readTestList($testList);
my $total_jobs = scalar(@testList);

print getRegressHeader() . "\n";
my @result = ();
($resultListing, $nbads, $unknown) = stringTestsResult(1,0,0,@result);
print "$resultListing";
my @more_finished_results = ();
my $jobs_finished=numJobsFinished(@testList);
my $sleep_time = ceil($total_jobs/100)*5;
while($jobs_finished<$total_jobs) {
   runTests(@testList);
   chdir "$CWD";
   open(JFILE, ">.jobNumbers.log") || die "can not open .jobNumbers.log for writing\n";
   for my $test (@testList) {
      print JFILE "$list_map{$test}->{jobNumber} $test\n" if (defined($list_map{$test}->{jobNumber}));
   }
   close(JFILE);
   @more_finished_results = getTestsResult(@testList);
   if(@more_finished_results) {
      push @result, @more_finished_results; # fill the result array as tests complete
      ($resultListing, $nbads, $unknown) = stringTestsResult(0,1,0,@more_finished_results);
      print "$resultListing";
   }
   $jobs_finished=numJobsFinished(@testList);
   #print "jobs_finished $jobs_finished total_jobs $total_jobs\n";
   sleep $sleep_time if($jobs_finished<$total_jobs);
}
($resultListing, $nbads, $unknown) = stringTestsResult(0,0,1,@result);
print "$resultListing\n";
@results = updateTestsResult(\@results, \@result);
$global_nbads += $nbads;
$global_unknown += $unknown;
%list_map = ();
$test_cnt=1;
($resultListing, $nbads, $unknown) = stringTestsResult(1,1,1,@results);
finish($nbads, $unknown);

################################################################################
# delEnvVars
sub delEnvVars()
{
   delete $ENV{CONFIG_DIR};
   delete $ENV{TESTNAME};
   delete $ENV{SEED};
   delete $ENV{LOCAL_VERIF_RUN_DIR};
   delete $ENV{MODULE_FILELIST};
   delete $ENV{TB_FILELIST};
   delete $ENV{MERGED_FILELIST};
   delete $ENV{USE_SCRATCH_AREA};
   delete $ENV{SIM_DIR};
   delete $ENV{XRUN_PROBE_OPTS};
   delete $ENV{XRUN_PROMOTE_TO_FATAL_LIST};
   delete $ENV{MODULE_NAME};
   delete $ENV{PROJECT_NAME};
   delete $ENV{TB_TOP};
   delete $ENV{OPTIONS};
   delete $ENV{VM_OPTIONS};
   delete $ENV{ROOT_DIR};
   delete $ENV{TB_RUN_OPTS};
   delete $ENV{TB_BUILD_OPTS};
   delete $ENV{TB_SIMV_OPTS};
   delete $ENV{SIMVISION_OPTS};
   delete $ENV{INDAGO_OPTS};
}


################################################################################
# numJobsFinished

sub numJobsFinished(\@)
{
   my ($listRef) = @_;
   my @list = @$listRef;
   my $jobs_finished = 0;

   for my $test (@list) {
      $jobs_finished++ if ($list_map{$test}->{finished});
   }
   return $jobs_finished;
}

################################################################################
# stringTestsResult

sub stringTestsResult($$$@)
{
   my ($prt_header, $prt_tests, $prt_footer, @result) = @_;
   my $passed = 0;
   my $failed = 0;
   my $killed = 0;
   my $unknown = 0;
   my $notfound = 0;
   my $comperr  = 0;

   my $output;
   my $st_us = 0;
   my $total_st = 0;
   my $total_st_us = 0;
   my $total_wall_time = 0;
   my $total_norm_st = 0;
   my $total_jobs = scalar(@testList);

   if($prt_header) {
      $output .= sprintf "Regression Results: %0d tests total \n\n", $total_jobs;
      $output .= sprintf "%-40s  %9s %12s %12s %12s %12s\n", "Testcase Name", "Status", "Sim_Time", "Wall_Time", "Seed", "Job_Cnt";
      $output .= sprintf '-'x105 . "\n";
   }
   for my $resR (@result) {
      my ($test, $status, $st, $wall_time, $seed) = @$resR;
      $total_st += $st;
      $st_us = int($st/1000);
      if($prt_tests) {
         $output .= sprintf "%-40s  %9s %10dus %12s %12d %6d\/%0d\n", $test, $status, $st_us, getTimeString($wall_time), $seed, $test_cnt++,$total_jobs;
         $list_map{$test}->{reported} = 1;
      }
      $total_st_us += $st_us;
      $total_wall_time += $wall_time;
      if ($status eq $TEST_FAILED) {
         $failed++;
      } elsif ($status eq $TEST_KILLED) {
         $killed++;
      } elsif ($status eq $TEST_NOTFOUND) {
         $notfound++;
      } elsif ($status eq $TEST_PASSED) {
         $passed++;
      } elsif ($status eq $TEST_COMPERR) {
         $comperr++;   
      } else {
         $unknown++;
      }
   }
   if($prt_footer) {
      $output .= sprintf '-'x105 . "\n";
      my $total_wall_time_str = getTimeString($total_wall_time);
      if($total_wall_time > 0) {
        $total_norm_st= int($total_st/$total_wall_time); # ns/seconds
      }
      my $timeLapsed = time() - $startTime;
      $output .= sprintf "%0d tests total. passed=%0d failed=%0d killed=%0d comperr=%0d missing=%0d unknown=%0d\n\n", $total_jobs, $passed, $failed, $killed, $comperr, $notfound, $unknown;
      $output .= sprintf "Total time lapsed: %s\n", getTimeString($timeLapsed);
      $output .= sprintf "Total sim time: %0d us\n", $total_st_us;
      $output .= sprintf "Total wall time: %s\n", $total_wall_time_str;
      $output .= sprintf "Total normalized sim time: %0d (ns/sec)\n", $total_norm_st;
   }
   return ($output, scalar(@result) - $passed, $unknown);
}


sub updateTestsResult($$)
{
   my ($old_result, $new_result) = @_;
   my @updated_result = ();
   my %list_map = ();
   my $test;
   my $status;
   my $st;
   my $wall_time;
   my $seed;
   my $resR;

   # get old statuses
   foreach $resR (@$old_result) {
      ($test, $status, $st, $wall_time, $seed) = @$resR;
      $list_map{$test}->{status} = $status;
      $list_map{$test}->{st} = $st;
      $list_map{$test}->{wall_time} = $wall_time;
      $list_map{$test}->{seed} = $seed;
   }
   # update new statuses
   foreach $resR (@$new_result) {
      ($test, $status, $st, $wall_time, $seed) = @$resR;
      $list_map{$test}->{status} = $status;
      $list_map{$test}->{st} = $st;
      $list_map{$test}->{wall_time} = $wall_time;
      $list_map{$test}->{seed} = $seed;
   }
   # recreate new result list
   foreach $test (sort keys %list_map) {
      my @result = ($test, $list_map{$test}->{status}, $list_map{$test}->{st}, $list_map{$test}->{wall_time}, $list_map{$test}->{seed});
      push @updated_result, \@result;
   }
   return @updated_result;
}

################################################################################
# usage()

sub usage()
{
   print <<EOS;
   $script <options>

Run regression.

Options:
    -h, --help:
      Display help and exit.

    --testlist <testlist>
      Use <testlist> as test list. The option is required.

    --cppopts <options>
      options that are passed into the cpp when it processes the testlist

   --licenses <options>
      licenses required for jobs

   --resources <options>
      additional resources required
        
   --queue
        LSF queue name.  Legal names are specific to the job distribution
        method used.  Please ask the farm administrator.
        Default is [$DEFAULT_JOB_QUEUE]

    --lsf 
        Use LSF for the farm,  default is AGE

    -q,--quiet 
       Send the clean and build jobs off to bsub and redirect the stdout
       and stderr to /dev/null

EOS
   exit 0;
}



################################################################################
sub getRegressHeader() {
   my $msgs;
      $msgs =<<EOS;

         REGRESSID: $regressionId
       LAUNCH HOST: $hostStamp
        START TIME: $dateStamp
             QUEUE: $jobQueue
         WORKSPACE: $ws_dir

              NOTE: To delete all jobs in this regression type the command below:
                    bkill -J $regressionId

EOS
   return $msgs;
}


################################################################################
# finish()

sub finish($$)
{
   my ($failed, $unknown) = @_; 
   my $timeLapsed = time() - $startTime;;
   my $filter_unknown;

   if ($failed) {
      if ($filter_unknown && ($failed == $unknown)) {
         print "UNKNOWN (in $timeLapsed seconds.)\n";
      } else {
         print "FAILED (in $timeLapsed seconds.)\n";
      }
   } else {
      print "PASSED (in $timeLapsed seconds.)\n";
   }
   exit $failed? 1 : 0;
}

################################################################################
# fail($)

sub fail($)
{
   my ($diag) = @_;
   warn "$script: $diag";
   finish(1, 0);
}


sub readTestList($)
{
   my ($listFile) = @_;

   open(FILE, "cpp $cppOpts -x assembler-with-cpp $listFile |") or
      die "readTestList: Error opening $listFile for reading";

   my @list;           # accumulated test list
   my ($orig_rtest, $rtest, $test, $testname, $tb, $cmd, $dep, $iter, $path, $seed);

   while (my $line = <FILE>) {
      chomp($line);
      # remove comments
      $line =~ s,#.*$,,;
      # strip white space
      $line =~ s,^\s+,,; $line =~ s,\s+$,,;
      # strip ending /
      $line =~ s,[\/]+$,,;
      next unless ($line ne '');

      my @dep_array;
      # if the test has the path then we extract the value and use it to append to test name 
      if ($line =~ m/\s*path\s*:\s*(\S+)\s*$/) {
          $path = $1;
          next;
      # test : $cmd : $dep : iter 
      } elsif ($line =~ m/\s*(\S+)\s*:\s*(.*)\s*:\s*(.*)\s*:\s*(.*)\s*$/) {
          $rtest = $1;
          $cmd = $2;
          $dep = $3;
          $iter = $4;
      # test : $cmd : $dep
      } elsif ($line =~ m/\s*(\S+)\s*:\s*(.*)\s*:\s*(.*)\s*$/) {
          $rtest = $1;
          $cmd = $2;
          $dep = $3;
          $iter = 1;
      # $test : $cmd
      } elsif ($line =~ m/\s*(\S+)\s*:\s*(.*)\s*$/) {
          $rtest = $1;
          $cmd = $2;
          $dep = "";
          $iter = 1;
      }
      $orig_rtest = $rtest;
      # get options that are sent to the make target
      my $opts = $cmd;
      $opts =~ s/make \S+//;
      $opts .= " REGRESSION=1";
      # get the root dir of the $path
      if($path) {
         $tb = basename($path);
         # need to uniquify the unit level TBs from verif/UVM TBs
         $tb = "u_$tb" if($path =~ m/^design\//);
         $rtest = "$tb\_$rtest";
         my @d_array = split(",",$dep);
         foreach my $d (@d_array) {
            $d = "$tb\_$d";  
            $d =~ s/\s*//g;
            push @dep_array, $d;
         }
      } else {
         my @d_array = split(",",$dep);
         foreach my $d (@d_array) {
            $d =~ s/\s*//g;
            push @dep_array, $d;
         }
      }
      #print Dumper(\@dep_array);
      if($iter>1) {
         $seed = int(rand(1000000)); 
      } else {
         $seed = 0; 
      }
      $test = $rtest;
      for(my $i=0;$i<$iter;$i++) {
         if($iter>1) {
            $test = "$rtest.$i";
         }
         if (!defined $list_map{$test}) {
            push @list, $test;
            $list_map{$test}->{cmd} = $cmd;
            $list_map{$test}->{opts} = $opts;
            $list_map{$test}->{deps} = [@dep_array];
            if($path) {
               $list_map{$test}->{path} = "$ws_dir/$path";
            } else {
               $list_map{$test}->{path} = "$CWD";
            }
            $list_map{$test}->{submitted} = 0;
            $list_map{$test}->{finished} = 0;
            $list_map{$test}->{reported} = 0;
            $list_map{$test}->{numpolls} = 0;
            $list_map{$test}->{clean} = 0;
            $list_map{$test}->{gen} = 0;
            $list_map{$test}->{build} = 0;
            $list_map{$test}->{run} = 0;
            $list_map{$test}->{status} = $TEST_UNKNOWN;
            # get TESTNAME if it is a test
            if($cmd =~ m/make\s+run/) {
               $list_map{$test}->{run} = 1;
               if($cmd =~ m/SEED=(\d+)/) {
                  $list_map{$test}->{seed} = $1;
               } else {
                  $list_map{$test}->{cmd} .= " SEED=$seed";
                  $list_map{$test}->{opts} .= " SEED=$seed";
                  $list_map{$test}->{seed} = $seed;
               }
               if($cmd =~ m/.* TESTNAME=(\S+).*/) {
                  $testname = $1;
               } else {
                  $testname=`cd $list_map{$test}->{path}; $MAKE echo_TESTNAME | sed 's/.*= //g'`;
               }
               chomp($testname);
               # magic to get the directory name to match the rtest (1st column in testlist), but still use the proper uvm test
               if(!($list_map{$test}->{path} =~ m/\/design\//)) {
                  $list_map{$test}->{opts} .= " TESTNAME=$orig_rtest UVM_TESTNAME=$testname";
                  $list_map{$test}->{cmd} .= " TESTNAME=$orig_rtest UVM_TESTNAME=$testname";
               }
               $list_map{$test}->{testname} = $testname;
               $list_map{$test}->{testdir}=`cd $list_map{$test}->{path}; $MAKE echo_SIM_RUN_DIR $list_map{$test}->{opts} | sed 's/.*= //g'`;
               chomp($list_map{$test}->{testdir});
               #print "testdir = $list_map{$test}->{testdir} \n";
               #$list_map{$test}->{testdir} = "$list_map{$test}->{path}/.sims/run_dir/$list_map{$test}->{testname}/$list_map{$test}->{seed}";
            } elsif($cmd =~ m/ build/) {
               $list_map{$test}->{build} = 1;
               $list_map{$test}->{builddir}=`cd $list_map{$test}->{path}; $MAKE echo_SIM_BUILD_DIR $list_map{$test}->{opts} | sed 's/.*= //g'`;
               chomp($list_map{$test}->{builddir});
               #print "builddir = $list_map{$test}->{builddir} end\n";
               #$list_map{$test}->{builddir} = "$list_map{$test}->{path}/.sims/build_dir";
            } elsif($cmd =~ m/ clean/) {
               $list_map{$test}->{clean} = 1;
            } elsif($cmd =~ m/make\s+gen_/) {
               $list_map{$test}->{gen} = 1;
            }
         } else {
            print "ERROR: test $test is already defined\n";
            exit(1);
         }
         $seed++;
      }
   }

   close FILE;
   #print Dumper(\%list_map);
   #exit(0);
   return @list;
}


################################################################################
# runTests()

sub runTests(\@)
{
   my ($listRef) = @_;
   my @list = @$listRef;

   # first run through all the cleans before attempting any other tests
   #for my $test (@list) {
   #   if($list_map{$test}->{clean} && !$list_map{$test}->{submitted}) {
   #      #print("cd $list_map{$test}->{path}; $list_map{$test}->{cmd} > /dev/null 2>&1\n");
   #      system("cd $list_map{$test}->{path}; $list_map{$test}->{cmd} > /dev/null 2>&1");
   #      $list_map{$test}->{submitted} = 1;
   #   }
   #}
   # now work on the other jobs
   for my $test (@list) {
      next if($list_map{$test}->{submitted});
      my $all_dep_finished = 1;
      for my $dep (@{$list_map{$test}->{deps}}) {
        #print "checking $test dep $dep status $list_map{$dep}->{finished}\n";
        $all_dep_finished = 0 if (!$list_map{$dep}->{finished}); 
      }
      # if the command is a clean or generate then run it locally, otherwise send it to farm
      if(($list_map{$test}->{clean} || $list_map{$test}->{gen} )  && !$list_map{$test}->{submitted}) {
        #print("cd $list_map{$test}->{path}; $list_map{$test}->{cmd} > /dev/null 2>&1\n");
        system("cd $list_map{$test}->{path}; $list_map{$test}->{cmd} > /dev/null 2>&1");
        $list_map{$test}->{submitted} = 1;
      } else {
        runTest($test) if($all_dep_finished);
      }
   }
}

################################################################################
# runTest()

sub runTest($)
{
   my ($test) = @_;
   my $origDir = cwd;
   my $extra_licenses = "";

   my $cmd = $list_map{$test}->{cmd};
   my $path = $list_map{$test}->{path};
   my $jobName = "$regressionId-$test";
   $jobName =~ s:/:_:g;

   chdir($path);
   my $dir = cwd;
   #print "Now in directory $dir\n";

   my $job;
   my $lic = "";

   if($use_lsf) {
     $lic = "-R \"rusage[Xcelium=1]\"" if($list_map{$test}->{run} || $list_map{$test}->{build});
     $job = "bsub -q regression -J $regressionId -n 1 -R \"rusage[mem=50G]\" $lic $cmd USE_LOCAL=1 REGRESSION=1 2>/dev/null";
   } else {
     $job = "qsub -V -cwd -b y -q short $cmd USE_LOCAL=1 REGRESSION=1";
   }
   #print("$test: $job\n");
   my $job_submitted=0;
   my $job_attempts = 0;
   while(!$job_submitted) {
      if($job_attempts > 100) {
         print "ERROR: unable to get the jobNumber from the farm for test $test after 100 job launch attempts\n";
         exit(1);
      }
      my @job_out = `$job`;
      $job_attempts++;
      #print "$job\n";
      #print "@job_out\n";
      foreach (@job_out) {
         chomp;
         #Job <11606> is submitted to queue <normal>.
         if (/^Job\s+<(\d+)>/ && $use_lsf) { $list_map{$test}->{jobNumber} = $1; }
         #Your job 1213335 ("xrun") has been submitted
         if (/^Your job\s+(\d+) .*/ && !$use_lsf) { $list_map{$test}->{jobNumber} = $1; }
      }
      if(defined $list_map{$test}->{jobNumber}) {
         $job_submitted = 1;
      }
   }
   #print "$list_map{$test}->{jobNumber} test=$test jobName=$jobName\n";
   $list_map{$test}->{jobName} = $jobName;
   $list_map{$test}->{submitted} = 1;
   chdir($origDir);
}

################################################################################
# getTestsResult()

sub getTestsResult(\@)
{
   my ($listRef) = @_;
   my @list = @$listRef;
   my @results;
   my @qstat = ();
   my $output_str;
   my $remaining_cnt=0;
   my $remainingFile = "$CWD/$script.remaining.poll.log";

  
   if($use_lsf) { 
      @qstat = `bjobs -a -J $regressionId 2>/dev/null`;
   } else {
      @qstat = `qstat -u $user`;
   }

   #if($pollResultOnly) {
   #   @qstat = `bjobs -u $user`;
   #} else {
   #   @qstat = `bjobs -J $regressionId`;
   #}

   #print "\n@qstat\n";

   if($use_lsf) {
      for my $test (@list) {
         next if($list_map{$test}->{reported} || !$list_map{$test}->{submitted});
         if($list_map{$test}->{clean} || $list_map{$test}->{gen}) {
            $list_map{$test}->{status} = $TEST_FINISHED;
         } else {
            $list_map{$test}->{status} = $TEST_NOTFOUND;
         }
         #print "checking test $test number $list_map{$test}->{jobNumber}\n";
         my $test_found=0;
         foreach(@qstat) {
           #JOBID   USER    STAT  QUEUE      FROM_HOST   EXEC_HOST   JOB_NAME   SUBMIT_TIME
           #11620   daniel. RUN   normal     vm-desktop- auc-edaexec *=UVM_NONE May 10 22:05
           if(/(\d+)\s+(\S+)\s+(\S+)\s+.*/) {
              if($list_map{$test}->{jobNumber} eq $1) {
                 #print "found test $test number $list_map{$test}->{jobNumber} and status is $3\n";
                 $test_found = 1;
                 if($3 eq "RUN") {
                    $list_map{$test}->{status} = $TEST_RUNNING;
                    $remaining_cnt++;
                 } elsif($3 eq "EXIT") {
                    $list_map{$test}->{status} = $TEST_FAILED;
                 } elsif($3 eq "DONE") {
                    $list_map{$test}->{status} = $TEST_FINISHED;
                 } elsif($3 eq "PEND" || $3 eq "PSUSP" || $3 eq "USUSP" || $3 eq "SSUSP") {
                    $list_map{$test}->{status} = $TEST_QUEUED;
                    $remaining_cnt++;
                 } else { 
                    $list_map{$test}->{status} = $TEST_FINISHED;
                 } 
                 $output_str .= sprintf "%-70s  %8s %9s\n", $test,$list_map{$test}->{status},$remaining_cnt;
                 last;
              }
            }
         }       
         $list_map{$test}->{numpolls}++ if(!$test_found);
         # if we haven't found the job then assume it is finished
         if(!$test_found && ($pollResultOnly || $list_map{$test}->{numpolls}>=5)) {
            #print "didn't find test $test number $list_map{$test}->{jobNumber} and assuming finished\n";
            $list_map{$test}->{status} = $TEST_FINISHED;
         }
         if ($list_map{$test}->{status} eq $TEST_FINISHED) {
            $list_map{$test}->{finished} = 1;
            my @res = getTestResult($test);
            unshift @res, $test;
            push @results, \@res;
         } elsif ($list_map{$test}->{status} eq $TEST_FAILED) {
            $list_map{$test}->{finished} = 1;
            my @res = ($test,$list_map{$test}->{status}, 0, 0, 0);
            push @results, \@res;
         } elsif($pollResultOnly) {
            my @res = ($test,$list_map{$test}->{status}, 0, 0, 0);
            push @results, \@res;
         }
         #print "test $test status $list_map{$test}->{status}\n";
      }

   } else {
      for my $test (@list) {
         next if($list_map{$test}->{reported} || !$list_map{$test}->{submitted});
         my $test_found=0;
         foreach(@qstat) {
           #   1066963 0.50500 xrun       daniel.marti r     04/21/2023 06:43:53 short@auc-edaexec17.husky-lake
           if(/\s*(\d+)+\s+\S+\s+\S+\s+(\S+)\s+(\S+)\s+.*/) {
              if($list_map{$test}->{jobNumber} eq $1) {
                 #print "found test $test number $list_map{$test}->{jobNumber} and status is $3\n";
                 $test_found = 1;
                 if($3 eq "r") {
                    $list_map{$test}->{status} = $TEST_RUNNING;
                 } else {
                    $list_map{$test}->{status} = $TEST_QUEUED;
                 }
                 $remaining_cnt++;
                 $output_str .= sprintf "%-70s  %8s %9s\n", $test,$list_map{$test}->{status},$remaining_cnt;
                 if($pollResultOnly) {
                    my @res = ($test,$list_map{$test}->{status}, 0, 0, 0);
                    push @results, \@res;
                 }
                 last;
              }
           }
         }
         $list_map{$test}->{numpolls}++ if(!$test_found);
         if(!$test_found && ($pollResultOnly || $list_map{$test}->{numpolls}>=3)) {
            #print "never found test $test number $list_map{$test}->{jobNumber}\n";
            $list_map{$test}->{status} = $TEST_FINISHED;
            $list_map{$test}->{finished} = 1;
            my @res = getTestResult($test);
            unshift @res, $test;
            push @results, \@res;
         }
         #print "test $test status $list_map{$test}->{status}\n";
      } 
   }
   if($remaining_cnt>0) {
      open(my $fh, ">$remainingFile") || die "Can't open $remainingFile file for writing $!\n";
      printf $fh "%-70s  %8s %9s\n", "Testcase Name", "Status", "Job_Cnt";
      printf $fh '-'x95 . "\n";
      print $fh $output_str;
      printf $fh '-'x95 . "\n";
      close($fh);
   } elsif(-f $remainingFile) {
      unlink $remainingFile;
   }
   return @results;
}

################################################################################
# getTestResult()

sub getTestResult($)
{
   my ($test) = @_;
   my $rlogF = 'xrun.log';
   #my $rlogF = "xrun.o$list_map{$test}->{jobNumber}";
   my $clogF = 'xrun.build.log';
   my $origDir = cwd;
   my $path = $list_map{$test}->{path};
   my $rootTest = $test;
   my $pass_stamped = 0;
   my $fail_stamped = 0;
   my $kill_stamped = 0;
   my $badly_stamped = 0;
   my $comperr_stamped = 0;

   my $st=0;
   my $wall_time=0;
   my $wall_time_found=0;
   my $cnt=0;
   my $status = $TEST_UNKNOWN;

   if(defined $list_map{$test}->{jobNumber} && !$use_lsf) {
      my $ageOutLog = "$path/make.o$list_map{$test}->{jobNumber}";
      my $ageErrLog = "$path/make.e$list_map{$test}->{jobNumber}";
      system("rm -f $ageOutLog $ageErrLog"); 
   }
   # if clean then return pass
   if($list_map{$test}->{clean} || $list_map{$test}->{gen}) {
      return ($TEST_PASSED, 0, 0, 0);
   # if build then we look at the builddir compile log
   } elsif($list_map{$test}->{build}) {
      # if we reach are here then job has finished
      while($cnt<12 && !chdir($list_map{$test}->{builddir})) {
         sleep 5;
         $cnt++;
         if($cnt==12) {
            if(!$pollResultOnly) {
               warn "$script: getTestResult: ",
               "cannot change to the test directory: $list_map{$test}->{builddir}: $!\n";
            }
            return ($TEST_NOTFOUND, 0,0,0);
         }
      }
      if (!-r $clogF) {
         chdir($origDir);
         return ($TEST_UNKNOWN, 0,0,0);
      }
      # just in case the run.log is not finished flushing out the final text
      # we need to loop with a delay a few times before declaring no cpu time
      $cnt=0;
      while($cnt<3 && !$wall_time_found) {
         if (-f $clogF) {
            my @tail = `tail -n 100 $clogF`;
            foreach(@tail) {
            # TOOL:   xrun(64)        22.03-s003: Exiting on Apr 21, 2023 at 05:43:21 UTC  (total: 00:00:04)
               if (m/TOOL:.*total: (\S+)\).*/) {
                  $wall_time = $1;
                  my ($hour,$min,$sec);
                  if($wall_time=~m,(\d+):(\d+):(\d+),) {
                    ($hour,$min,$sec) = ($1,$2,$3);
                  }
                  $wall_time=$hour*3600+$min*60+$sec;
                  $wall_time_found=1; 
               }
            }
         }
         if(!$wall_time_found) {
            sleep 10;
            $cnt++;
         }
      } 
      if(!$wall_time_found) {
         print "WARNING: unable to get wall_time from $clogF";
      }
      # look for any *E, in the compile log file
      my @cErrors = `grep " *E," $clogF`;
      if(@cErrors) {
         $status = $TEST_FAILED;
      } else {
         $status = $TEST_PASSED;
      }
      chdir($origDir);
      return ($status, 0, $wall_time, 0);
   # else it must be a test so look at the testdir run log
   } else {
      # if we reach are here then job has finished
      $cnt=0;
      if ($cnt<12 && !chdir($list_map{$test}->{testdir})) {
         sleep 5;
         $cnt++;
         if($cnt==12) {
            if(!$pollResultOnly) {
               warn "$script: getTestResult: ",
               "cannot change to the test directory: $list_map{$test}->{testdir}: $!\n";
            }
            return ($TEST_NOTFOUND, 0,0,0);
         }
      }
      if (!-r $rlogF) {
         chdir($origDir);
         return ($TEST_UNKNOWN, 0,0,0);
      }
      # just in case the run.log is not finished flushing out the final text
      # we need to loop with a delay a few times before declaring no cpu time
      $cnt=0;
      while($cnt<3 && !$wall_time_found) {
         if (-f $rlogF) {
            my @tail = `tail -n 100 $rlogF`;
            foreach(@tail) {
               # TOOL:   xrun(64)        22.03-s003: Exiting on Apr 21, 2023 at 05:43:21 UTC  (total: 00:00:04)
               if (m/TOOL:.*total: (\S+)\).*/) {
                  $wall_time = $1;
                  my ($hour,$min,$sec);
                  if($wall_time=~m,(\d+):(\d+):(\d+),) {
                    ($hour,$min,$sec) = ($1,$2,$3);
                  }
                  $wall_time=$hour*3600+$min*60+$sec;
                  $wall_time_found=1; 
               }
               #UVM_INFO example.sv(146) @ 500050000: uvm_test_top [test_00] ----           TEST PASS           ----
               #TEST PASSED
               #* Test PASSED
               #PASSED!
               if ((m/^UVM_INFO .* uvm_test_top .* TEST (\S+).*/i) ||
   		(m/^TEST (\S+).*/) || 
   		(m/^\* Test (\S+).*/) || 
   		(m/^(\S+)!/))  {
                  my $stamp = uc($1);
                  if ($stamp eq 'PASSED' || $stamp eq 'PASS') {
                     $status = $TEST_PASSED;
                  } elsif ($stamp eq 'FAILED' || $stamp eq 'FAIL') {
                     $status = $TEST_FAILED;
                  } else {
                     $status = $TEST_UNKNOWN;
                  }
               }
               #Simulation complete via $finish(1) at time 6630 NS + 0
               if (m/^Simulation complete .*at time (\S+) NS .*/) {
                  my $st_local = $1;
                  $st    = int($st_local); # value comes in ns
               } elsif (m/^Simulation complete .*at time (\S+) PS .*/) {
                  my $st_local = $1;
                  $st    = int($st_local) / 1000; # convert to ns 
               } elsif (m/^Simulation complete .*at time (\S+) FS .*/) {
                  my $st_local = $1;
                  $st    = int($st_local) / 1000000; # convert to ns 
               }
            }
         } 
         if(!$wall_time_found) {
            sleep 10;
            $cnt++;
         }
      }
      #SVSEED set randomly from command line: 507536884
      my $rseed = `grep SVSEED $rlogF | cut -d ":" -f 2`; 
      $rseed =~ s/^\s+//;
      chdir($origDir);
      return ($status, $st, $wall_time, $rseed);
   }
}


################################################################################
# getTimeString()

sub getTimeString($) {
   my ($seconds) = @_;
   my $rtHour = int($seconds/3600);
   my $rtMin = int(($seconds%3600)/60);
   my $wall_time_str = $rtHour . "h" . $rtMin . "m" . $seconds%60 . "s";
   return $wall_time_str;
}
