package App::perl2scl;
# ABSTRACT: Convert non-SCL SPEC files to SCL SPEC files
use strict;
use warnings;
use utf8;

use File::Slurp;
use Getopt::Long;
use Term::ANSIColor;

# Common SCL stuff
my $p = '%{?scl_prefix}';
# %{?scl_prefix}perl(:MODULE_COMPAT_%(%{?scl:scl enable %{scl} '}eval "`%{__perl} -V:version`"; echo $version%{?scl:'}))
my $eo = "%{?scl:scl enable %{scl} '}";
my $ec = "%{?scl:'}";

sub go {
    # Default to coloured output
    my $color = 1;
    my $quiet = 0;
    my $inplace = 0;
    my $dryrun = 0;
    # Gather any extra info
    my @info;
    GetOptions('color!' => \$color,
        'dryrun' => \$dryrun,
        'quiet' => \$quiet,
        'inplace' => \$inplace);
    my $file = $ARGV[0] or die "No SPEC file specified!";
    -f -r $file or die "Cannot open `$file'!";
    my $data = read_file($file);
    my ($name) = $data =~ /Name:\s*([^\n]+)/s;
    # Now let's do all the ugly bits
    # NOTE: These packages are intended for SCL only
    # We're in a collection, so add the necessary stuff
    $data = '%{?scl:%scl_package '.$name."}\n\n".$data;
    # And convert Name
    $data =~ s/(Name:[ \t]*)perl/$1${p}perl/s;
    # Convert perl [Build]Requires, Obsoletes and Provides
    $data =~ s/((Conflicts|Obsoletes|Provides|Requires):[ \t]*)(?<perl>perl(-devel|-\S+)?)\b/$1$p$+{perl}/sg;
    $data =~ s/((?:Conflicts|Obsoletes|Provides|Requires):[ \t]*)(perl\()/$1$p$2/sg;
    # Convert MODULE_COMPAT
    $data =~ s/Requires:(\h*)[^\n]*MODULE_COMPAT_[^\n]*/Requires:$1${p}perl(:MODULE_COMPAT_\%(${eo}eval "\$(perl -V:version)";echo \$version${ec}))/sg;
    # Convert %if 0%(perl -e 'print $] > N.NNN') conditions
    $data =~ s/^%if 0%\(perl -e 'print \$\] > (\d\.\d+)'\)/%if 0%(${eo}perl -e %{?scl:'"}'%{?scl:"'}print \$] > $1%{?scl:'"}'%{?scl:"'}${ec})/mg;
    # Convert %check
    my $check;
    $check++ if $data =~ s/(make test|\.\/Build test)([^\n]*)/${eo}$1$2${ec}/s;
    # Convert %build
    my $build;
    $build++ if $data =~ s/(%{__)?perl}? Makefile.PL(?<pargs>[^\n]*)\n+make(?<margs>[^\n]*)/${eo}perl Makefile.PL$+{pargs} && make$+{margs}${ec}/s;
    $build++ if $data =~ s/(%{__)?perl}? Build.PL(?<pargs>[^\n]*)\n+\.\/Build(?<bargs>)/${eo}perl Build.PL$+{pargs} && .\/Build$+{bargs}${ec}/s;
    # Convert %install
    my $install;
    $install++ if $data =~ s/(make (?:pure_)?install[^\n]*)/${eo}$1${ec}/s;
    $install++ if $data =~ s/\.\/Build install([^\n]*)/${eo}.\/Build install$1${ec}/s;
    # Convert %files
    $data =~ s/%(\{?)license\1(\h)/%doc$2/sg;
    # Fix filters with ^perl
    $data =~ s/\^(perl\\*\()/^$p$1/sg;

    # Warn on suspicious things
    push @info, "Suspicious `perl' calls detected: ${^MATCH}!"
        if $data =~ /.*(?<!\Q${eo}\E)perl -[^V].*/p;
    push @info, "Either `if' or `deprecate' used."
        if $data =~ /perl(\(if\)|\(deprecate\))/s;
    push @info, 'Explicit non-perl() style conflicts, [build]requires, provides, obsoletes or blocks: ' . ${^MATCH} . '.'
        if $data =~ /(Conflicts|Requires|Provides|Obsoletes|Blocks):( |\t)*[^\s%].*/p;
    push @info, '%{rhel} macro used.'
        if $data =~ /\%\{\??rhel\}/s;
    push @info, '%{__perl} macro used: ' . ${^MATCH}
        if $data =~ /.*%(?:\{\??)?__perl(?!\w).*/p;
    push @info, 'Only one type of filters used.'
        if ($data =~ /__(requires|provides)_exclude/s &&
            $data !~ /filter_from_(requires|provides)/s) ||
           ($data !~ /__(requires|provides)_exclude/s &&
            $data =~ /filter_from_(requires|provides)/s);
    push @info, '%{fix_shbang_line} macro used.'
        if $data =~ /%(\{)?\??fix_shbang_line\b/s;
    push @info, 'Converting %check failed'
        unless $check;
    push @info, 'Converting %build failed'
        unless $build;
    push @info, 'Converting %install failed'
        unless $install;
    push @info, 'A perl-%{macro} style package name detected'
        if $data =~ /perl-\%/s;
    push @info, '%{license} macro used: ' . ${^MATCH}
        if $data =~ /(?<!%)%\{?\??license\}?.*/p;

    if (@info && !$quiet) {
        print STDERR color('yellow') if $color;
        print STDERR join ("\n", map { "$name: $_" } @info) . "\n";
        print STDERR color('reset') if $color;
    }
    return if $dryrun;
    if ($inplace) {
        write_file($file, $data)
    } else {
        print $data;
    }
}

1;

__END__

=encoding utf8

=head1 NAME

perl2scl - Convert non-SCL SPEC files to SCL SPEC files

=head1 SYNOPSIS

B<perl2scl> S<[ B<--[no]color]> ]>  S<[ B<-diq> ]> I<specfile>

=head1 DESCRIPTION

F<perl2scl> attempts to convert a regular SPEC file used in Fedora or EPEL
distributions to a version compatible with Software Collections (SCL).

The conversion process is simple and naïve, mostly consisting of preset
substitions.

The script also tries to detect bits that may require your extra attention
and warns about these.

=head1 OPTIONS

Most of the options are available in both a I<short> and a I<long> form.

=over 4

=item B<--color>, B<--nocolor>

Enable or disable colored output.  The default is enabled.

=item B<-d>, B<--dryrun>

Don't output anything but noticed.

=item B<-i>, B<--inplace>

Write the conversion output to the SPEC file directly rather than printing
it on the standard output.

=item B<-q>, B<--quiet>

Don't print any notices.

=back

=head1 SEE ALSO

spec2scl

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2014 Petr Šabata <contyk@redhat.com>

See LICENSE for licensing details.

=cut
