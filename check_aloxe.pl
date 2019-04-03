#!/usr/bin/perl

###  check_aloxe.pl, version: 1.1, 3 Apr 2019
# 
# Copyright: C. Ntokos, University of Ioannina, Greece
#
# A check plugin for Nagios/Icinga to monitor Alcatel OXE (OminPCX Enterprise) PBXs.
# This plugin is built using the Monitoring::Plugin module.
#
# It reports for a given PBX host, based on a mode option:
# - coupler (i.e. cards) service status for a given crystal and a list of coupler types or a 
#   coupler number
# - terminal (i.e. phones, faxes etc) status statistics for the PBX
# - trunk group channel usage statistics for a given trunk group number
# - link channel usage statistics for a given pair of crystal and coupler
# Possible future implementation:
# - crystal topology info for a given PBX
#
##############################################################################

use strict;
use warnings;


# PBX telnet credentials
my $TELNET_USER = 'user';
my $TELNET_PASS = 'pass';

use Monitoring::Plugin;
use Net::Telnet ();

use vars qw($VERSION $PROGNAME $verbose $timeout);

$VERSION = '1.1';

use File::Basename;
$PROGNAME = basename($0);


my $usage = "Usage: %s [-v|--verbose] [-t|--timeout <timeout>] -H|--host <host> -m|--mode <mode>
       ( [-i|--crystal <crystal>] [-y|--ctype <coupler types>] | [-c|--coupler] [-r|--rdescr
         <remote pbx description] ) | [-g|--trkgroup <trunk group>] [-h|--help]
";
my $blurb = "This plugin connects to an Alcatel OXE PBX and reports:
 - coupler (i.e. cards) service status for a given crystal and a list of coupler types or a 
   coupler number
 - terminal (i.e. phones, faxes etc) status statistics for the PBX
 - trunk group channel usage statistics for a given trunk group number
 - link channel usage statistics for a given pair of crystal and coupler
";

my $help_txt = "
  NOTE: timeout value must be at least 3 secs to allow for minimum telnet timeout of 1 secs

    Examples:
$PROGNAME -H x.x.x.x -m coupler -i 0 -c INTIPA,INTOF_A,PRA2,UA32
    Checks coupler status on crystal number 0, for couplers with type INTIPA or INTOF_A or PRA2 or UA32 and reports statistics
$PROGNAME -H x.x.x.x -m coupler -i 0 -y 1
    Checks coupler status on crystal number 0, coupler number 1 and reports statistics

$PROGNAME -H x.x.x.x -m terminal -i 1
    Reports statistics by terminal types for terminals on crystal number 1
$PROGNAME -H x.x.x.x -m terminal
    Reports statistics by terminal types for all terminals on the PBX

$PROGNAME -H x.x.x.x -m trunk -g 1
    Reports channel statistics for trunk group 1

$PROGNAME -H x.x.x.x -m link -i 0 -c 27 -r 'RPBX (0-19)'
    Reports channel statistics for link designated by crystal 0, coupler 27.
    Also display on the result the given description of the remote PBX link info
";

# define and get the command line options.
my $plugin = Monitoring::Plugin->new(
                 usage => $usage,
                 version => $VERSION,
                 blurb => $blurb,
                 extra => $help_txt
);


# Define and document the valid command line options
$help_txt = "-H, --host IPADDR
   IP address of PBX to be checked";

$plugin->add_arg(
           spec => 'host|H=s',
           help => $help_txt,
           required => 1
);

$help_txt = "-m, --mode STRING
   a keyword to specify what to check:
\tcoupler\t\tPBX card service status for the given crystal
\tlink\t\ttlink channel statistics for the given crystal-coupler numbers
\tterminal\ttotal terminal status statistics for the PBX
\ttrunk\t\ttrunk channel statistics for the given trunk group number";

$plugin->add_arg(
           spec => 'mode|m=s',
           help => $help_txt,
           required => 1
);

$help_txt = "-i, --crystal INTEGER
   PBX crystal number to check.
   If mode=coupler or mode=link this option is required.
   If mode=terminal and this option is omitted then the plugin reports terminal statistics for
   the entire PBX.";

$plugin->add_arg(
           spec => 'crystal|i=i',
           help => $help_txt,
);

$help_txt = "-c, --coupler INTEGER
   Coupler number for which to check the service status or link channel statistics.
   Required option if mode=link.
   If mode=coupler you can either use this option or the --ctype option.";

$plugin->add_arg(
           spec => 'coupler|c=i',
           help => $help_txt,
);

$help_txt = "-y, --ctype TYPE1,TYPE2,...
   a list of coupler types for which to check the service status.
   If mode=coupler you can either use this option or the --coupler option.";

$plugin->add_arg(
           spec => 'ctype|y=s',
           help => $help_txt,
);

$help_txt = "-g, --trkgroup INTEGER
   PBX trunk group number for which to check and report channel usage.
   If there are no FREE channels the check result will be WARNING (i.e. threshold=100%).
   Required option if mode=trunk.";

$plugin->add_arg(
           spec => 'trkgroup|g=i',
           help => $help_txt,
);

$help_txt = "-r, --rdescr STRING
   Remote PBX description to print on plugin output.";

$plugin->add_arg(
           spec => 'rdescr|r=s',
           help => $help_txt,
);


# Functions

sub check_extra_opts {

   return "No host specified" if (! defined ($plugin->opts->host));

   return "Option --mode is mandatory" if (! defined ($plugin->opts->mode));

   if ($plugin->opts->mode eq "coupler") {
      $plugin->shortname('Couplers');

      return "Mode=coupler requires option --crystal" if (! defined ($plugin->opts->crystal));

      if ((! defined ($plugin->opts->ctype)) && (! defined ($plugin->opts->coupler))) {
         return "Mode=coupler requires option --ctype or --coupler";
      }

      return "Invalid option --trkgroup (-g) for mode=coupler" if (defined ($plugin->opts->trkgroup));
      return "Invalid option --rdescr (-r) for mode=coupler" if (defined ($plugin->opts->rdescr));
   }
   elsif ($plugin->opts->mode eq "terminal") {
      $plugin->shortname('Terminals');

      return "Invalid option --ctype (-y) for mode=terminal" if (defined ($plugin->opts->ctype));
      return "Invalid option --coupler (-c) for mode=terminal" if (defined ($plugin->opts->coupler));
      return "Invalid option --trkgroup (-g) for mode=terminal" if (defined ($plugin->opts->trkgroup));
      return "Invalid option --rdescr (-r) for mode=terminal" if (defined ($plugin->opts->rdescr));
   }
   elsif ($plugin->opts->mode eq "trunk") {
      $plugin->shortname('Trunk');

      return "Mode=trunk requires option --trkgroup" if (! defined ($plugin->opts->trkgroup));

      return "Invalid option --crystal (-i) for mode=trunk" if (defined ($plugin->opts->crystal));
      return "Invalid option --ctype (-y) for mode=trunk" if (defined ($plugin->opts->ctype));
      return "Invalid option --coupler (-c) for mode=trunk" if (defined ($plugin->opts->coupler));
      return "Invalid option --rdescr (-r) for mode=trunk" if (defined ($plugin->opts->rdescr));
   }
   elsif ($plugin->opts->mode eq "link") {
      $plugin->shortname('Link');

      return "Mode=link requires option --crystal" if (! defined ($plugin->opts->crystal));
      return "Mode=link requires option --coupler" if (! defined ($plugin->opts->coupler));

      return "Invalid option --ctype (-y) for mode=link" if (defined ($plugin->opts->ctype));
      return "Invalid option --trkgroup (-g) for mode=link" if (defined ($plugin->opts->trkgroup));
   }
   else {
      $plugin->shortname($plugin->opts->mode);
      return "Unknown mode=" . $plugin->opts->mode;
   }

   if ($plugin->opts->timeout < 3) {
      return "Timeout value " . $plugin->opts->timeout . " is less than minimum (3 secs)";
   }

}


sub check_couplers {
   my @lines = @_;

   my ($cd, $msg, $p_out) = (undef, undef, undef);
   my ($coupl_ok, $coupl_all) = (undef, undef);
   
   if (defined($plugin->opts->ctype)) {
      for my $t (split(/,/, $plugin->opts->ctype)) {
         $$coupl_ok{$t} = 0;
         $$coupl_all{$t} = 0;
      }
   }

   my $col_offset = 0;

   for my $l (@lines) {
      chomp($l);

      $l =~ s/^\s+//;
      next if (length($l) == 0);

      my @f = split(/\|/, $l);

      #remove the 4th column (i.e. 'hw type' column) if output has 6 columns
      splice(@f, 4, 1) if ($#f == 6);

      next if ($#f != 5);
   
      $f[3] =~ s/\s//g;

      next if ((defined($plugin->opts->ctype)) && (! defined($$coupl_all{$f[3]})));

      $f[2] =~ s/\s//g;

      next if ((defined($plugin->opts->coupler)) && ($plugin->opts->coupler ne $f[2]));

      $f[4] =~ s/(^\s+)|(\s+$)//g;

      printf("Found coupler number %s, type %s, status %s: ", $f[2], $f[3], $f[4]) if $plugin->opts->verbose;
      
      $$coupl_all{$f[3]} = 0 if (!defined($coupl_all));
      $$coupl_all{$f[3]}++;

      $$coupl_ok{$f[3]} = 0 if (!defined($coupl_ok));

      my $coupler_name = $plugin->opts->crystal . "-" . $f[2] . '-' .  $f[3];
   
      if (index($f[4], "IN SERVICE") >= 0) {
         printf("OK\n") if $plugin->opts->verbose;

         $plugin->add_message(OK, "");

         $$coupl_ok{$f[3]}++;
      }
      elsif (index($f[4], "OUT OF SERV") >= 0) {
         printf("CRITICAL\n") if $plugin->opts->verbose;

         $plugin->add_message(CRITICAL, " " . $coupler_name . ": OFF");
      }
      elsif ((index($f[4], "NOT INIT") < 0) &&
             (index($f[4], "MAO FILE") < 0) &&
             (index($f[4], "OPS FILE") < 0)) {
         printf("WARNING\n") if $plugin->opts->verbose;

         $plugin->add_message(WARNING, " " . $coupler_name . ": " . $f[4]);
      }
      else {
         printf("Unknown...ignoring\n") if $plugin->opts->verbose;
   
         $$coupl_all{$f[3]}--;
      }
   }

   my $ncouplers = 0;
   $p_out = "";

   foreach my $k (sort keys %$coupl_all) {
      if ($$coupl_all{$k} > 0) {
         $p_out .= $k . "=" . $$coupl_ok{$k} . ";0;0;0;" . $$coupl_all{$k} . " ";
         $ncouplers += $$coupl_all{$k};
      }
   }

   if (! $ncouplers) {
      $cd = UNKNOWN;
      if (defined($plugin->opts->ctype)) {
         $msg = "No couplers matching list: " . $plugin->opts->ctype;
      }
      else {
         $msg = "No coupler number " . $plugin->opts->coupler . " found";
      }
   }
   else {
      ($cd, $msg) = $plugin->check_messages(join => '', ok => 'All ' . $ncouplers . ' couplers OK');
   }
  
   return ($cd, $msg, $p_out);

} #check_couplers


sub check_terminals  {
   my @lines = @_;

   my ($cd, $msg, $p_out) = (undef, undef, undef);
   my ($termtypes_ok, $termtypes_all) = (undef, undef);
  
   if ($plugin->opts->verbose) {
      printf("Checking terminals");
      printf(" on Crystal %s", $plugin->opts->crystal) if defined($plugin->opts->crystal);
      printf("\n");
   }
         
   for my $l (@lines) {
      chomp($l);

      $l =~ s/^\s+//;
      next if (length($l) == 0);

      my @f = split(/\|/, $l);

      next if ($#f != 5);
   
      $f[4] =~ s/\s//g;

      next if ((length($f[4]) == 0) || ($f[4] !~ /^\d+$/));

      $f[3] =~ s/\s|\)//g;
      $f[3] =~ s/\(/\-/g;

      $$termtypes_all{$f[3]} = 0 if (! defined($$termtypes_all{$f[3]}));
      $$termtypes_all{$f[3]}++;

      $$termtypes_ok{$f[3]} = 0 if (! defined($$termtypes_ok{$f[3]}));

      $f[5] =~ s/\s|\.//g;

      if (length($f[5]) == 0) {
         $$termtypes_ok{$f[3]}++;
      }
   }

   my ($nterms, $nterms_ok, $ntermtypes) = (0, 0, 0);
   $p_out = "";

   foreach my $k (sort keys %$termtypes_all) {
      $p_out .= $k . "=" . $$termtypes_ok{$k} . ";0;0;0;" . $$termtypes_all{$k} . " ";

      $nterms += $$termtypes_all{$k};
      $nterms_ok += $$termtypes_ok{$k};
      $ntermtypes ++;
   }

   if ($nterms > 0) {
      my $t_rstr = $ntermtypes . " types, " . $nterms . " total terminals, ";
      $t_rstr .= $nterms_ok . " OK, " . ($nterms - $nterms_ok) . " not OK";

      $plugin->add_message(OK, $t_rstr);

      ($cd, $msg) = $plugin->check_messages();
   }
   else {
      $cd = UNKNOWN;

      if (defined($plugin->opts->crystal)) {
         $msg = "No terminals found on crystal " . $plugin->opts->crystal;
      }
      else {
         $msg = "No terminals found on this PBX";
      }
   }
  
   return ($cd, $msg, $p_out);

} #check_terminals


sub check_trunkgroup  {
   my @lines = @_;

   my ($cd, $msg, $p_out) = (undef, undef, undef);

   my @trunk_states = ();
   my $trunk_name = "";
   my ($n_states, $n_nonfree) = (0, 0);

   printf("Checking trunk group %s:\n", $plugin->opts->trkgroup) if $plugin->opts->verbose;

   for my $l (@lines) {
      chomp($l);

      $l =~ s/^\s+//;
      next if (length($l) == 0);

      $l =~ s/\|//g;

      my @f = split(/:/, $l);

      next if ($#f != 1);
   
      $f[0] =~ s/(^\s+)|(\s+$)//g;

      if ($f[0] eq "Trunk group name") {
         $trunk_name = $f[1];
         $trunk_name =~ s/(^\s+)|(\s+$)//g;

         printf("Trunk group has name: %s\n", $trunk_name) if $plugin->opts->verbose;

         next;
      }

      next if ($f[0] ne "State");

      $f[1] =~ s/(^\s+)|(\s+$)//g;
      next if (length($f[1]) == 0);

      @f = split(/\s+/, $f[1]);

      for my $s (@f) {
         $n_nonfree++ if ($s ne "F");

         push(@trunk_states, $s);
      }

      printf("Added %s trunk channel states\n", $#trunk_states + 1 - $n_states) if $plugin->opts->verbose;

      $n_states = $#trunk_states + 1;
   }

   if ($#trunk_states < 0) {
      $cd = UNKNOWN;
      $msg = "No trunk channel states found";
      $p_out = "";
   }
   else {
      if ($n_nonfree < $n_states) {
         $plugin->add_message(OK, $n_states - $n_nonfree . " Free channels");
      }
      else {
         $plugin->add_message(WARNING, "NO Free channels");
      }

      $p_out = "NonFree=" . $n_nonfree . ";" . $n_states . ";0;0;" . $n_states;

      ($cd, $msg) = $plugin->check_messages();
   }

   $trunk_name = ": " . $trunk_name if (length($trunk_name) > 0);
  
   $plugin->shortname("TG " . $plugin->opts->trkgroup . $trunk_name);

   return ($cd, $msg, $p_out);

} # check_trunkgroup


sub check_link  {
   my @lines = @_;

   my ($cd, $msg, $p_out) = (undef, undef, undef);
   my @link_states = ();
   my ($n_states, $n_nonfree) = (0, 0);

   my $link_name = "Link from: (" . $plugin->opts->crystal . "-" . $plugin->opts->coupler . ")";
   $link_name .= " to: " . $plugin->opts->rdescr if (defined($plugin->opts->rdescr));
   
   printf("Checking %s\n", $link_name) if $plugin->opts->verbose;

   for my $l (@lines) {
      chomp($l);

      $l =~ s/^\s+//;
      next if (length($l) == 0);

      $l =~ s/\|//g;

      my @f = split(/\s\s+/, $l);

      next if ($#f < 5);
   
      shift(@f) if (length($f[0]) == 0);

      $f[0] =~ s/(^\s+)|(\s+$)//g;

      next if ($f[0] ne "State");

      shift(@f);

      for my $s (@f) {
         $n_nonfree++ if ($s ne "F");

         push(@link_states, $s);
      }

      printf("Added %s link channel states\n", $#link_states + 1 - $n_states) if $plugin->opts->verbose;

      $n_states = $#link_states + 1;
   }

   if ($#link_states < 0) {
      $cd = UNKNOWN;
      $msg = "No link channel states found";
      $p_out = "";
   }
   else {
      if ($n_nonfree < $n_states) {
         $plugin->add_message(OK, $n_states - $n_nonfree . " Free channels");
      }
      else {
         $plugin->add_message(WARNING, "NO Free channels");
      }

      $p_out = "NonFree=" . $n_nonfree . ";" . $n_states . ";0;0;" . $n_states;

      ($cd, $msg) = $plugin->check_messages();
   }
  
   $plugin->shortname($link_name);

   return ($cd, $msg, $p_out);

} # check_link


# MAIN program

# Parse arguments and process standard ones (e.g. usage, help, version)
$plugin->getopts;


# Check extra command line options
my $err_message = check_extra_opts();
$plugin->plugin_die($err_message) if (length($err_message) > 0);

if ($plugin->opts->verbose) {
   printf("Running in MODE: %s for HOST: %s\n", $plugin->opts->mode, $plugin->opts->host);
   printf("Will check CRYSTAL: %s", $plugin->opts->crystal) if (defined($plugin->opts->crystal));
   printf(", and COUPLER types: %s", $plugin->opts->ctype) if (defined($plugin->opts->ctype));
   printf(", and COUPLER: %s", $plugin->opts->coupler) if (defined($plugin->opts->coupler));
   printf("Will check TRUNK group: %s", $plugin->opts->trkgroup) if (defined($plugin->opts->trkgroup));
   printf("\n");
}

# Open telnet session
my $telnet = new Net::Telnet(
                Timeout => $plugin->opts->timeout > 10 ? 10 : $plugin->opts->timeout - 2,
                Errmode => 'return',
                Prompt => '/\(\d\d\d\)xa00\d\d\d> $/'
);

printf("Connecting to host %s\n", $plugin->opts->host) if $plugin->opts->verbose;
if (! $telnet->open($plugin->opts->host)) {
   $plugin->plugin_die("Can't connect to host " . $plugin->opts->host . ", " . $telnet->errmsg);
}

printf("Login to host %s\n", $plugin->opts->host) if $plugin->opts->verbose;
if (! $telnet->login($TELNET_USER, $TELNET_PASS)) {
   $plugin->plugin_die("Can't login to host " . $plugin->opts->host . ", " . $telnet->errmsg);
}

# Issue appropriate command to PBX
my $tool_cmd = "";
if ($plugin->opts->mode eq "coupler") {
   $tool_cmd = "config";
}
elsif ($plugin->opts->mode eq "terminal") {
   $tool_cmd = "listerm";
}
elsif ($plugin->opts->mode eq "link") {
   $tool_cmd = "trkstat";
}
elsif ($plugin->opts->mode eq "trunk") {
   $tool_cmd = "trkstat " . $plugin->opts->trkgroup;
}

$tool_cmd .= " " . $plugin->opts->crystal if defined($plugin->opts->crystal);
$tool_cmd .= " " . $plugin->opts->coupler if defined($plugin->opts->coupler);

printf("Sending command %s to host %s\n", $tool_cmd, $plugin->opts->host) if $plugin->opts->verbose;
my @outp = $telnet->cmd($tool_cmd);

if ($#outp < 1) {
   $plugin->plugin_die("Error issuing cmd " . $tool_cmd . " to host " . $plugin->opts->host . ", " . $telnet->errmsg);
}

close($telnet);


my ($code, $message, $perf_output) = (undef, undef, undef);

if ($plugin->opts->mode eq "coupler") {
   ($code, $message, $perf_output) = check_couplers(@outp);
}
elsif ($plugin->opts->mode eq "link") {
   ($code, $message, $perf_output) = check_link(@outp);
}
elsif ($plugin->opts->mode eq "trunk") {
   ($code, $message, $perf_output) = check_trunkgroup(@outp);
}
elsif ($plugin->opts->mode eq "terminal") {
   ($code, $message, $perf_output) = check_terminals(@outp);
}

$plugin->plugin_die($message) if ($code == UNKNOWN);

$message .= " | " . $perf_output;
$plugin->plugin_exit($code, $message);


exit 99;
