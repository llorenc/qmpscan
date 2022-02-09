#!/usr/bin/perl -w
# Escaneja/llegeix estat, les estacions wifi.
# (c) Llorenç Cerdà. Octubre, 2012.

use strict ;
use Getopt::Long; # Getopt::Long::Configure ("gnu_getopt");
use Scalar::Util qw(reftype);
use IO::Handle ;
use POSIX ;
use Time::HiRes qw(usleep);

sub usage( ) ;
sub mprint( $ ) ;
sub gprint( $ ) ;
sub catch_int() ; $SIG{INT} = \&catch_int ;
sub read_record( )  ;
sub read_iw_fields( )  ;
sub read_iwlist_fields( )  ;
sub print_record( $ ) ;
sub gather() ;
#-----------------------------------------------------------------------
my($period) = 1 ; # seconds
my($maxmac) = 100 ;
my $numsamp = 5 ;
#-----------------------------------------------------------------------
my($iface) = "wlan0" ;

my($command) = $0 ; $command =~ s%.*/(\w+)%$1% ; 
my($args) ;
foreach my $argnum (0 .. $#ARGV) {
    $args .= " $ARGV[$argnum]" ;
}
my(%opts) ;
my $res = GetOptions(\%opts,
                    'help|h',
		    'iw',
                    'essid|e:s',
                    'exclude|x:s',
                    'save|s:s',
                    'iface|i:s',
                    'freq|f:s',
                    'verbose|v',
                    'gnuplot|g',
                    'rhost|r:s',
                    'sudo',
		    'period|p:s'
                   ) ;
usage() if ((!$res) || $opts{help}) ;
$iface = $opts{iface} if defined($opts{iface}) ;
$period = $opts{period} if defined($opts{period}) ;

#-----------------------------------------------------------------------
my ($wcmd, $wpar, $wpat) =
    (defined($opts{iw}) ?
     ## ('iw', "dev $iface station dump ", '^Station (..:..:..:..:..:..)') :
     ('iw', "$iface scan ", '^BSS (..:..:..:..:..:..)') :
     ('iwlist', "$iface scan ", 'Address: (.*)$')) ;

my $wpath = "if [ -x /sbin/$wcmd ] ; then echo '/sbin' ; elif [ -x /usr/sbin/$wcmd ] ; then echo '/usr/sbin' ; else echo '' ; fi" ;
my $sshcmd ;
my $scmd ;

if($opts{rhost}) {
  $sshcmd = 'ssh -MNf -o "ControlPath=/tmp/ssh-%r-%h-%p" -T ' . $opts{rhost} ;
  system($sshcmd) and die("Cannot execute ssh\n") ;
  $scmd = 'ssh -o "ControlMaster=no" -o "ControlPath=/tmp/ssh-%r-%h-%p" ' . $opts{rhost} . " " ;
  # ssh -oControlMaster=yes -oControlPath=/tmp/ssh-%r-%h-%p $opts{rhost} " ;
  $wpath = "$scmd \"$wpath\"" ;
} else {
  $scmd = "" ;
}

$wpath = `$wpath` ;
chomp $wpath ;
if($wpath eq '') {
    die "Not found $wcmd\n" ;
} else {
    $wcmd = "$scmd $wpath/$wcmd $wpar" ;
}
$wcmd = 'sudo' .  $wcmd if defined($opts{sudo}) ;
# my $wcmd = "sudo /sbin/iwlist $iface scan " ;
# $wcmd .= " 2>/dev/null" if ! $opts{verbose} ;
#-----------------------------------------------------------------------
my $callgnuplot = "| gnuplot -persist" ; $callgnuplot .= " 2>/dev/null" if ! $opts{verbose} ;
my(%db, $k, $f, @input_array) ;
my($line, $lnum) ;
my($time0) = time ;
my $printcount = 0 ;
my $gathercount = 0 ;
my(%wstadb, @wsta) ;

if (defined $opts{save}) {
  open(OFILE, "> " . getpid() . "-$opts{save}")
    or die "Cannot open pipe \"$opts{save}\"\n" ;
}
my $gnufile = "$command-" . getpid() . ".tmp" ;

if (defined $opts{gnuplot}) {
  print "open gnuplot, title: $args\n" ;
  print "gnuplot file: /tmp/$gnufile\n" ;
  open(GNUFILE, "> /tmp/$gnufile")
    or die "Cannot open file '/tmp/$gnufile'\n" ;
  open(GNUPIPE, $callgnuplot) ;
  print GNUPIPE <<EOM;
set title '$args'
set grid
set style line 1 lc rgb "dark-violet" lw 2
set style line 2 lc rgb "sea-green" lw 2
set style line 3 lc rgb "cyan" lw 2
set style line 4 lc rgb "dark-red" lw 2
set style line 5 lc rgb "blue" lw 2
set style line 6 lc rgb "dark-orange" lw 2
set style line 7 lc rgb "black" lw 2
set style line 8 lc rgb "goldenrod" lw 2
set style line 9 lc rgb "brown" lw 2
set term x11 persist
EOM
	;
  print GNUPIPE "set datafile missing 'NaN' \n" ;
  GNUPIPE->autoflush(1) ;
}

my($print) = 0 ;
mprint "# File gererated by $command $args\n" ;
mprint "# Using pipe: $wcmd\n" ;
mprint "# " . `date` ;
my ($min, $max) = (-90, -85) ;
while (1) {
  $lnum = 0 ;
  @input_array = gather() ; ++$gathercount ;
  if(@input_array) {
    my(%gather, $k) ;
    my($now) = time - $time0 ;
    while (@input_array) {
      my $node_key = read_record() ;
      next if ! defined $node_key ;
      next if ! defined $wstadb{$node_key}->{power} ;
      $gather{$node_key} = $wstadb{$node_key}->{power} ;
      if(!defined($wstadb{$node_key}->{max_power}) ||
	 ($wstadb{$node_key}->{power} > $wstadb{$node_key}->{max_power})) {
	$wstadb{$node_key}->{max_power} = $wstadb{$node_key}->{power}
      }
      if($opts{gnuplot}) {
	if ($min > $wstadb{$node_key}->{power}-0.1) {
	  $min =  $wstadb{$node_key}->{power}-0.1 ;
	} elsif ($max < $wstadb{$node_key}->{power}+0.1) {
	  $max =  $wstadb{$node_key}->{power}+0.1 ;
	}
      }
    }
    # print "$now\t" ;
    # print "wsta: $#wsta\n" ;
    if ($#wsta >= 0) {
      my($pline) = sprintf "%3d ", ++$printcount ;
      my $gprint = 0 ;
      foreach $k (0..$#wsta) {
	if (defined($wsta[$k]) && defined($gather{$wsta[$k]})) {
	  $pline .= sprintf "%3d ", $gather{$wsta[$k]} ;
	  $gprint = 1 ;
	} else {
	  $pline .= ' NaN ' ;
	}
      }
      $pline .= "\n" ;
      if ($gprint) {
	gprint($pline) ;
      } else {
	mprint $pline ;
      }
      usleep($period*1000) ;
    } else {
      usleep($period*250) ;
    }
  }
}
#print @input_array ;

#-----------------------------------------------------------------------
sub catch_int() {
  my $sshpid ;
  if(defined($opts{rhost})) {
    foreach(`ps aux | egrep "$sshcmd"`) {
      $sshpid = $_ ;
      $sshpid =~ s/^\D+(\d+)\s.*$/$1/ ;
      print "# kill $sshpid\n" ;
      kill 1, $sshpid ;
    }
  }
  my $k ;
  foreach $k (sort {$wstadb{$a}->{essid} cmp $wstadb{$b}->{essid}} keys %wstadb) {
    print_record($wstadb{$k}) ;
  }
  if(defined($opts{save})) {
    close OFILE ;
    print "Output file: " . getpid() . "-$opts{save}\n" ;
  }
  unlink "/tmp/$gnufile" or warn "Could not unlink /tmp/$gnufile: $!"
    if defined $opts{gnuplot} ;
  exit() ;
}

sub buildgnucmd() {
  my $i ;
  my $maxq = $wstadb{$wsta[0]}->{essid} ;
  my $cmd = "'/tmp/$gnufile' " ;
  foreach $i (0..$#wsta) {
      $cmd = $cmd . ',"" ' if($i > 0)  ;
      $cmd = $cmd . 'u 1:($' . ($i+2) . ')' . 
	  " w lines ls " . ($i+1) . "t \"${wstadb{$wsta[$i]}->{essid}}\"" ;
  }
  return $cmd ;
}

sub mprint( $ ) {
  print STDOUT $_[0] ;
  print OFILE $_[0] if defined $opts{save} ;
  if(defined($opts{gnuplot})) {
    print GNUFILE $_[0] ;
  }
}

sub gprint( $ ) {
  mprint $_[0] ;
  GNUFILE->autoflush(1);
  my $cmd = buildgnucmd() ;
  if (defined($opts{gnuplot})) {
    print GNUPIPE <<EOM;
set xlabel "sample number"
set ylabel "power"
set key below
set yrange [$min:$max]
plot $cmd
EOM
	;
    GNUPIPE->autoflush(1);
  }
}

#-----------------------------------------------------------------------
sub gather() {
  open(FILE, "$wcmd|")
    || die "Cannot open pipe \"$wcmd\"\n" ;
  return(<FILE>) ;
}

sub print_record( $ ) {
  if(defined($_[0])) {
    my($k) ;
    mprint "#-----------------------------------------------------------------------\n" ;
    foreach $k (sort {$a cmp $b} keys %{$_[0]}) {
      if(defined($_[0]->{$k})) {
	mprint "# $k: " ;
	if(ref($_[0]->{$k}) eq 'ARRAY') {
	  mprint(join(" ", @{$_[0]->{$k}})) ;
	} else {
	  mprint $_[0]->{$k} ;
	}
	mprint "\n" ;
      }
    }
  }
}

sub get_line() {
  ++$lnum ;
  $line = shift(@input_array) ;
}

sub unget_line() {
  --$lnum ;
  unshift(@input_array, $line) ;
}

sub read_record( ) {
  my($record, $address) ;
  my($end) = 0 ;
  do {
    get_line() ;
    if(defined($line) && ($line =~ /$wpat/)) {
      $address = uc($1) ;
      ## print "address: " . $address . "\n" ;
      if($address eq "02:CA:FF:EE:BA:BE") {
	$record = (defined($opts{iw}) ? read_iw_fields() : read_iwlist_fields()) ;
	if(defined($record)) {
	  $end = 1 ;
	} else {
	  print "Error in line: $line\n" ;
	}
      }
    }
  } while ($line && !$end) ;
  return undef if ! defined $record ;
  $record->{address} = $address ;
  my $node_key = $record->{essid} . '-' . $address ;
  return(undef) if(defined($opts{essid}) &&
	    (!defined($record->{essid}) ||
	     ($record->{essid} =~ /^\s*$/) || !($record->{essid} =~ /$opts{essid}/))) ;
  return(undef) if(defined($opts{exclude}) && 
	    (!defined($record->{essid}) || ($record->{essid} =~ /$opts{exclude}/))) ;
  return(undef) if(!defined($record->{power}) || ($record->{power} == 0)) ;
  if(!defined($wstadb{$node_key})) {
    print "adding wsta-add: $node_key\n" ;
    $wstadb{$node_key} = $record ;
    if(($#wsta+1) < $maxmac) {
      my $pline ;
      push(@wsta, $node_key) ;
      $pline = "# time " ;
      foreach $k (@wsta) {
	$pline .= (" " . $wstadb{$k}->{essid}) ;
      }
      mprint($pline . "\n") ;
    }
  } # elsif ($wstadb{$node_key}->{$measure} < $record->{$measure}) {
  if(!$wstadb{$node_key}) {
    $wstadb{$node_key} = $record ;
  } else {
    $wstadb{$node_key}->{power} = $record->{power} ;
  }
  return($node_key) ;
}

sub read_iwlist_fields()  {
  my($essid, $channel, $freq, $power) ;
  my($end) = 0 ;
  do {
    get_line() ;
    if($line =~ /\s*(\S*)[:=](.*)$/) {
      $channel = $2 if $1 eq "Channel" ;
      $essid = $2 if $1 eq "ESSID" ;
      $freq = $2 if $1 eq "Frequency" ;
      if($1 eq "Quality") {
	$line =~ /Signal level=([-]*\d+)\b/ ;
	$power = $1 ;
      }
    }
    if (defined($line) && ($line =~ /Cell \d+ - Address:/)) {
      ##print "read_iwlist_fields line: $lnum\n" ;
      unget_line() ;
      $end = 1 ;
    }
  } until (!@input_array || $end) ;
  $essid =~ s/"//g ;
  return({
	  essid => $essid,
	  channel => $channel,
	  freq => $freq,
	  power => $power
	 }) ;
}

sub read_iw_fields()  {
  my($essid, $channel, $freq, $power) ;
  my($end) = 0 ;
  do {
    get_line() ;
    if($line =~ /[\s\W]*([^:=]*)[:=](.*)$/) {
      $channel = $2 if $1 eq "primary channel" ;
      $essid = $2 if $1 eq "SSID" ;
      $freq = $2 if $1 eq "freq" ;
      if($1 eq "signal") {
	$power = $2 ;
	$power =~ s/ dBm$// ;
      }
    }
    if (defined($line) && ($line =~ /$wpat/)) {
      ##print "read_iwlist_fields line: $lnum\n" ;
      unget_line() ;
      $end = 1 ;
    }
  } until (!@input_array || $end) ;
  $essid =~ s/"//g ;
  if($essid && $freq && $power) {
    return({
	    essid => $essid,
	    freq => $freq,
	    channel => $channel,
	    power => $power
	   }) ;
  } else {
    return undef ;
  }
}

sub usage() {
  die <<"EOM" ;
Usage: $command [options]
 Options
   iw: use iw to gather info (default iwlist).
   essid <regexp>: track ESSID matching <regexp>.
   exclude <regexp>: exclude ESSID matching <regexp>.
   save <file>: save to file <file>.
   iface <iface>: Use <ifce> (default wlan0).
   verbose: verbose.
   freq <freq>: egrep <freq>.
   gnuplot: pipe to gnuplot to generate a real time graphic.
   rhost <host>: ssh to <host>.
   sudo: use sudo.
   period <period (seconds)>.
 Examples:
  $command -vgar root\@c6 -e '^qMp$|qMp-ns'
  $command --iw -vgr root\@nbgv
  $command --iw -vgr root\@nbc6 --essid 'BCNgrVia'
  $command -vgr root\@upcc6 -m Txbps
EOM
}
