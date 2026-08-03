#!/bin/perl -w
use strict;

use JSON;
use Data::Dumper;

my $root_dir = $ENV{ROOT_DIR};

while (scalar(@ARGV)) {
   my $arg = shift @ARGV;
   if ($arg eq '--root_dir') {
      $root_dir = shift @ARGV;
   }
}

# my $json_file = "$root_dir/.methodics/ws_manifest.json";
# 
# my $ips_ref = decode_json(`cat $json_file`); 
# 
# my $chip = $ips_ref->{top_ipv}->{ipid}->{ip};
# 
# $chip =~ s/_.*//g;
# $chip = uc($chip);
# 
# printf("$chip\n");

printf("bombur_tc\n");

