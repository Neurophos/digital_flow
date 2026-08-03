#!/usr/bin/env perl

use strict;
use warnings;
use YAML::XS 'LoadFile';
use Data::Dumper;
use Cwd;
use Getopt::Long;

my $DBG = 0;

###############################################
# Help messaging
###############################################
sub usage() {
    print "\n";
    print "usage: build_regs.pl <filenames> where: \n";
    print "\n";
    print "    filenames (required): \n";
    print "        -yaml=<yaml file to process>\n";
    print "        -top=<top level module name. if not provided, the top tag from the yaml file is used>\n";
    print "        -syn (if present, will include any _syn modules and exclude _sim_only)\n";
    print "\n";
}


###############################################
# Process the command-line arguments
###############################################
my $yaml_file = '';
my $top = '';
my $syn = '';

GetOptions ('yaml=s'            => \$yaml_file, 
            'top=s'             => \$top, 
            'syn'               => \$syn,
            'h|help'            => \&usage
        ) or usage();

if ($DBG) { 
    print "\n";
    print "yaml         $yaml_file\n";
    print "top          $top\n";
    print "syn          $syn\n";
    print "\n";
}

if (($yaml_file eq '') || ($top eq '')) {
    usage();
    exit;
}

###############################################
# Check validity of input file and options
###############################################
die "Input YAML file does not exist!\n\n" if (! -e $yaml_file);

my $proj_base_dir='';

# Determine the project base-directory name based on where we could possibly be
if (! defined $ENV{ROOT_DIR}) { 
    $proj_base_dir = getcwd;
    $proj_base_dir =~ s/(verif|impl|design|common).*//g;
    die "ERROR - could not determine project base directory! \n\n" if (! -d $proj_base_dir);
} else { 
    $proj_base_dir = $ENV{ROOT_DIR};
}

# Create the empty lists I will need later
my @reg_dirs = ();

# Determine the type of YAML file from the YAML itself
# Open the design config
my %yaml = %{ LoadFile( $yaml_file ) };

# Design or Testbench YAML - die if neither
die if ((!exists $yaml{yaml_type}) || (($yaml{yaml_type} ne 'tb') && ($yaml{yaml_type} ne 'design')));


###############################################
# Now do the work 
###############################################

# First look to see if we are parsing design modules
# Create hash for the modules only
my $modules;
if ($yaml{yaml_type} eq 'design') {
    $modules = \%{$yaml{modules}};
} else {
    $modules = \%{$yaml{testbenches}};
}

# If the top module isn't defined from the command line, extract from YAML
if ($top eq '') { 
    $top = $yaml{top};
    die if ($top = $yaml{top});
}

# Need to parse the common modules first to put first in the manifest list
if ($yaml{yaml_type} eq 'design') {
    # Create hash for the common modules
    my %common;
    if (exists $yaml{common}) { 
        %common = %{$yaml{common}};
    }

    # Now loop through any common modules and add to lists
    foreach my $mod (keys %common) { 
        # print "$mod\n";
        parse_modules(\%common, $mod);
    }
}

# Recursively parse the design
parse_modules($modules, $top, 0, '');
    
# Function to recursively parse the YAML and fill arrays
sub parse_modules {
    my %mods        = %{$_[0]};
    my $mod_name    = $_[1];
    my $hier        = $_[2];
    my $path_remap  = $_[3];

    print ("mod_name = $mod_name\n") if ($DBG);

    if (exists $mods{$mod_name}{regs}) { 
        foreach my $dir (@{$mods{$mod_name}{regs}}) { 
            $dir =~ s/^design/$path_remap\/design/g if ($hier);

            my $tmp = $proj_base_dir . $dir . "/";
            die "ERROR - REGS directory $tmp does not exist...\n\n" if (! -e $tmp);
            if ( ! grep( /^$tmp$/, @reg_dirs) ) {
                push (@reg_dirs, $tmp);
                build_regs_rtl($tmp, $mod_name);
            }
        }
    }

    if (exists $mods{$mod_name}{yaml}) { 
        print "   doing a hier yaml module\n" if ($DBG);
        my $tmp = $proj_base_dir . $mods{$mod_name}{yaml};
        die "ERROR - YAML file $tmp does not exist...\n\n" if (! -e $tmp);
        my $tmp_path_remap = $mods{$mod_name}{path_remap} || 
            die "ERROR - path_remap: does not exist for hier YAML entry $mod_name...\n\n";
        parse_hier_yaml($tmp, $mod_name, $tmp_path_remap);
    }

    # If no instances/submodules, all done
    return if ((($syn eq '') and (! exists $mods{$mod_name}{submodules}) and (! exists $mods{$mod_name}{submodules_sim_only})) or
               (($syn ne '') and (! exists $mods{$mod_name}{submodules}) and (! exists $mods{$mod_name}{submodules_syn_only})));

    # Loop through submodules
    if ($syn eq '') {
        foreach my $sub (@{$mods{$mod_name}{submodules_sim_only}}) {
            # print ("    submodule_sim_only = $sub\n") if ($DBG);
            die "\n\nERROR - exiting due to no definition for module $sub! \n\n" if (! exists $ {\%mods}{$sub});
            parse_modules(\%mods, $sub, $hier, $path_remap);
        }
    } else {
        foreach my $sub (@{$mods{$mod_name}{submodules_syn_only}}) {
            # print ("    submodule_syn_only = $sub\n") if ($DBG);
            die "\n\nERROR - exiting due to no definition for module $sub! \n\n" if (! exists $ {\%mods}{$sub});
            parse_modules(\%mods, $sub, $hier, $path_remap);
        }
    }

    # Now do common submodules for both sim and syn
    foreach my $sub (@{$mods{$mod_name}{submodules}}) {
        # print ("    submodule = $sub\n") if ($DBG);
        die "\n\nERROR - exiting due to no definition for module $sub! \n\n" if (! exists $ {\%mods}{$sub});
            parse_modules(\%mods, $sub, $hier, $path_remap);
    }
}

sub uniquify {
    my @array = @{$_[0]};

    my %seen = ();
    my @array_no_dup = grep { ! $seen{ $_ }++ } @array;

    return @array_no_dup;
}

sub build_regs_rtl {
    my $reg_dir = $_[0];
    my $design  = $_[1];

    print "Info: building registers at $reg_dir\n";

    my $curdir = getcwd;
    chdir ($reg_dir) or die "ERROR - could not change to reg directory $reg_dir\n";
    my $output = `make`;
    chdir ($curdir);
}


sub parse_hier_yaml {
    my $hier_yaml_file  = $_[0];
    my $mod             = $_[1];
    my $remap           = $_[2];

    print "      $hier_yaml_file -> filename\n" if ($DBG);
    print "      mod = $mod\n" if ($DBG);
    print "      remap = $remap\n" if ($DBG);

    # Determine the type of YAML file from the YAML itself
    my %hier_yaml = %{ LoadFile( $hier_yaml_file ) };

    # Design or Testbench YAML - die if neither
    die if ((!exists $yaml{yaml_type}) || (($yaml{yaml_type} ne 'tb') && ($yaml{yaml_type} ne 'design')));

    # Now go parse the submodule in the hierarchical YAML file
    my $hier_modules;

    if ($hier_yaml{yaml_type} eq 'design') {
        $hier_modules = \%{$hier_yaml{modules}};
    } else {
        $hier_modules = \%{$hier_yaml{testbenches}};
    }

    # print Dumper($hier_modules);

    parse_modules($hier_modules, $mod, 1, $remap);
}

