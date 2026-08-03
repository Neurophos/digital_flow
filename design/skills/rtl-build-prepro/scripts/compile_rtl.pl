#!/usr/bin/env perl
# =======================================================================================
# Copyright (C) Neurophos, Inc - All Rights Reserved
# Proprietary and confidential
# -------------------------------------------------------------------------------
# TITLE : RTL Compilation Script
# FILE  : compile_rtl.pl
# DESCRIPTION : Compiles all RTL modules in the design directory
#              
# STANDARD    : Perl
# REVISIONS   :
# VERSION     : 1.0
# =======================================================================================

use strict;
use warnings;
use Getopt::Long;
use File::Spec;
use File::Find;
use File::Basename;

# ============================================================================
# Configuration
# ============================================================================
my $VERSION = "1.0";
my $PROGRAM_NAME = basename($0);

# ============================================================================
# Global Variables
# ============================================================================
my $design_dir;
my $build_dir;
my $log_dir;
my $verbose = 0;
my $help = 0;

# ============================================================================
# Command Line Options
# ============================================================================
GetOptions(
    'design-dir=s'  => \$design_dir,
    'build-dir=s'   => \$build_dir,
    'log-dir=s'     => \$log_dir,
    'verbose'       => \$verbose,
    'help'          => \$help
) or die "Error in command line arguments\n";

# ============================================================================
# Help and Usage
# ============================================================================
if ($help) {
    print_help();
    exit 0;
}

# Validate required parameters
unless ($design_dir && $build_dir) {
    print "Error: Missing required parameters\n\n";
    print_help();
    exit 1;
}

$log_dir ||= File::Spec->catdir($build_dir, "logs");

# ============================================================================
# Main Execution
# ============================================================================
print "MSIC RTL Compilation Script v$VERSION\n";
print "=====================================\n\n";

# Create directories
system("mkdir -p $build_dir") unless -d $build_dir;
system("mkdir -p $log_dir") unless -d $log_dir;

# Find all Makefiles in design directory
my @makefiles = find_makefiles($design_dir);
print "Found " . scalar(@makefiles) . " RTL modules to compile\n\n";

# Compile each module
my $success_count = 0;
my $total_count = scalar(@makefiles);

foreach my $makefile (@makefiles) {
    my $module_dir = dirname($makefile);
    my $module_name = basename($module_dir);
    
    print "Compiling module: $module_name\n" if $verbose;
    
    if (compile_module($module_dir, $module_name)) {
        $success_count++;
        print "  ✓ $module_name compiled successfully\n";
    } else {
        print "  ✗ $module_name compilation failed\n";
    }
}

print "\nCompilation Summary:\n";
print "  Successful: $success_count/$total_count\n";
print "  Failed: " . ($total_count - $success_count) . "/$total_count\n";

if ($success_count == $total_count) {
    print "\nAll modules compiled successfully!\n";
    exit 0;
} else {
    print "\nSome modules failed to compile. Check logs for details.\n";
    exit 1;
}

# ============================================================================
# Subroutines
# ============================================================================

sub print_help {
    print <<EOF;
Usage: $PROGRAM_NAME [OPTIONS]

Compiles all RTL modules in the design directory.

OPTIONS:
    --design-dir DIR     Design directory containing RTL modules (required)
    --build-dir DIR      Build directory for compilation artifacts (required)
    --log-dir DIR        Log directory for compilation logs (optional)
    --verbose            Enable verbose output
    --help               Show this help message

EXAMPLES:
    $PROGRAM_NAME --design-dir design \\
                  --build-dir build \\
                  --verbose

EOF
}

sub find_makefiles {
    my ($dir) = @_;
    my @makefiles;
    
    find(sub {
        if ($_ eq "Makefile" && -f $File::Find::name) {
            push @makefiles, $File::Find::name;
        }
    }, $dir);
    
    return @makefiles;
}

sub compile_module {
    my ($module_dir, $module_name) = @_;
    
    my $log_file = File::Spec->catfile($log_dir, "${module_name}_compile.log");
    my $cmd = "cd $module_dir && make compile 2>&1 | tee $log_file";
    
    my $result = system($cmd);
    
    if ($result == 0) {
        return 1;  # Success
    } else {
        return 0;  # Failure
    }
}

# ============================================================================
# End of Script
# ============================================================================
