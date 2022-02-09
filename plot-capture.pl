#!/usr/bin/perl -w
# Llegeix les captures generades amb qmpscan.pl
# (c) Llorenç Cerdà. Febrer, 2022.

use strict ;
use Getopt::Long; # Getopt::Long::Configure ("gnu_getopt");
use Scalar::Util qw(reftype);
use IO::Handle ;
use POSIX ;

#-----------------------------------------------------------------------
sub usage( ) ;
sub mprint( $ ) ;
sub gprint( $ ) ;
my($period) = 1 ; # seconds
#-----------------------------------------------------------------------
my ($min, $max) = (0, -90) ;
my($command) = $0 ; $command =~ s%.*/(\w+)%$1% ; 
my($args) ;
foreach my $argnum (0 .. $#ARGV) {
    $args .= " $ARGV[$argnum]" ;
}
my(%opts) ;
my $res = GetOptions(\%opts,
                    'help|h',
                    'save|s',
                   ) ;
usage() if ((!$res) || $opts{help}) ;
usage() if $#ARGV != 0 ;
-f $ARGV[0] || $ARGV[0] ne "-" && die "File \"$ARGV[0]\" not found\n" ;
my $title = $args ;
my $gnufile = "$command-" . getpid() . ".tmp" ;
my $callgnuplot = "| gnuplot -persist" ;
my(%wstadb, @wsta) ;
my $printcount = 0 ;

print "open gnuplot\n" ;
open(GNUFILE, "> /tmp/$gnufile")
  or die("Cannot open file '/tmp/$gnufile'\n") ;
my $pid = open(GNUPIPE, $callgnuplot) ;
print GNUPIPE <<EOM;
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

sub buildgnucmd() {
  return if $#wsta <= 0 ;
  my $i ;
  my $maxq = $wstadb{$wsta[0]}->{essid} ;
  my $cmd = "'/tmp/$gnufile' " ;
  foreach $i (0..$#wsta) {
      $cmd = $cmd . ',"" ' if($i > 0)  ;
      $cmd = $cmd . 'u 1:($' . ($i+2) . ')' . 
	  " w lines ls " . ($i+1) . "t \"${wstadb{$wsta[$i]}->{essid}}\"" ;
  }
  return $cmd . "\n";
}

sub gprint( $ ) {
  return if $#wsta <= 0 ;
  mprint $_[0] ;
  GNUFILE->autoflush(1);
  my $cmd = buildgnucmd() ;
  print GNUPIPE <<EOM;
set title '$title'
set xlabel "sample number"
set ylabel "power"
set key below
set yrange [$min:$max]
plot $cmd
EOM
  ;
  GNUPIPE->autoflush(1);
}

sub save_plot($) {
  my $filen = shift ;
  print GNUPIPE <<EOM;
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
set terminal pdf size 15,10
set output "$filen"
EOM
  ;
  gprint("") ;
}

sub mprint( $ ) {
  print GNUFILE $_[0] ;
}

while(<>) {
  if(/^# (.*\d\d:\d\d:\d\d.*)$/) {
    $title .= ", $1" ;
  }
  if(/^# time (.*)$/) {
    my $l = $1 ;
    while($l =~ /(\S+)/g ) {
      if(!$wstadb{$1}) {
        $wstadb{$1}->{essid} = $1 ;
        push(@wsta, $1) ;
      }
    }
  } else {
    my $l = $_ ;
    if(/^\s*\d+\D+(-.*)$/) {
      my $l = $1 ;
      while($l =~ /(\d+)\D/g ) {
        my $power = -$1 ;
	if ($min > $power-0.1) {
	  $min =  $power-0.1 ;
	} elsif ($max < $power+0.1) {
	  $max =  $power+0.1 ;
	}
      }
    }
    if($#wsta >= 0) {
      chomp($l) ;
      gprint("$l\n") ;
    }
  }
}

sub usage() {
  die <<"EOM" ;
Usage: $command [options] <capture file>
 Options
   save: save file.
EOM
}

(my $fname = $args) =~ s/^\s*(\S+)\.[^.]+$/$1/ ; $fname .= ".pdf" ;
if(defined($opts{save})) {
  print "$fname\n" ;
  save_plot($fname) ;
}

close GNUPIPE ;
unlink "/tmp/$gnufile" or warn "Could not unlink /tmp/$gnufile: $!"
