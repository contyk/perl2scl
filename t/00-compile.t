use strict;
use warnings;
use Test::More tests => 2;
use Test::Script;

for my $file (qw(
    bin/perl2scl
    lib/App/perl2scl.pm
    )) {
        script_compiles($file, "$file compiles");
    }
