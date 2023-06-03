{ pkgs, ...}: pkgs.writers.writePerlBin "replace" { } ''
use 5.30.0;
use strict;
use warnings;

# simple textual replacement; return 1 if no replacements were made

use File::Basename  qw( dirname );
use Getopt::Long    qw( GetOptions :config bundling no_ignore_case 
                                           prefix_pattern=--|- );
use File::Temp      qw( tempfile );

my (%fromto, $from, $to, $output, $overwrite);
GetOptions( 'from=s'      => \$from
          , 'to=s'        => \$to
          , 'fromto=s%'   => \%fromto
          , 'output|o=s'  => \$output
          , 'overwrite|O' => \$overwrite
          )
  or die "options parsing failed\n";

die "please supply --from"
  unless keys %fromto or defined $from;
die "please supply --to"
  unless keys %fromto or defined $to;

if ( defined $from ) {
  if ( defined $to ) {
    $fromto{$from} = $to;
  } else {
    die "--from requires --to"
  }
} elsif ( defined $to ) {
  die "--from requires --to"
}

my $c = 0;

my $fh = *STDOUT{IO};

my $tempfn; # END { unlink $tempfn if defined $tempfn; }
END {
  if ( defined $output and defined $tempfn ) {
    rename $tempfn, $output;
  }
}

if ( defined $output ) {
  die "not overwriting extant '$output'\n"
    if ! $overwrite and -e $output;
  my $dir = dirname $output;
  die "no such dir '$dir'\n"
    unless -e $dir;
  die "not a dir '$dir'\n"
    unless -d $dir;
  die "cannot write dir '$dir'\n"
    unless -w $dir;
  ($fh,$tempfn) = tempfile('replace-XXXX', DIR=>dirname($output));
}

while (<>) {
  chomp;
  while (my ($from,$to) = each %fromto) {
    $c += s/$from/$to/g;
  }
  say $fh $_;
}

close $fh
  or die "close failed: $!\n";

exit 1
  if $c == 0;
''

# Local Variables:
# mode: perl
# End:
