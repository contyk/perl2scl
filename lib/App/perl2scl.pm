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
    # Convert perl [Build]Requires and Provides
    $data =~ s/(Requires:[ \t]*)(?<perl>perl(-devel)?)\n/$1$p$+{perl}\n/sg;
    $data =~ s/(Requires:[ \t]*)(perl\()/$1$p$2/sg;
    $data =~ s/(Provides:[ \t]*)(perl\()/$1$p$2/sg;
    # Convert MODULE_COMPAT
    $data =~ s/Requires:(\h*)[^\n]*MODULE_COMPAT_[^\n]*/Requires:$1${p}perl(:MODULE_COMPAT_\%(${eo}eval "\$(perl -V:version)";echo \$version${ec}))/sg;
    # Convert %check
    my $check;
    $check++ if $data =~ s/(make test|\.\/Build test)([^\n]*)/${eo}$1$2${ec}/s;
    # Convert %build
    my $build;
    $build++ if $data =~ s/(%{__)?perl}? Makefile.PL(?<pargs>[^\n]*)\n+make(?<margs>[^\n]*)/${eo}perl Makefile.PL$+{pargs}; make$+{margs}${ec}/s;
    $build++ if $data =~ s/(%{__)?perl}? Build.PL(?<pargs>[^\n]*)\n+\.\/Build(?<bargs>)/${eo}perl Build.PL$+{pargs}; .\/Build$+{bargs}${ec}/s;
    # Convert %install
    my $install;
    $install++ if $data =~ s/make pure_install([^\n]*)/${eo}make pure_install$1${ec}/s;
    $install++ if $data =~ s/\.\/Build install([^\n]*)/${eo}.\/Build install$1${ec}/s;
    # Fix filters with ^perl
    $data =~ s/\^(perl\\*\()/^$p$1/sg;

    # Warn on suspicious things
    push @info, "Suspicious `perl' calls detected!"
        if $data =~ /perl -[^V]/s;
    push @info, "Either `if' or `deprecate' used."
        if $data =~ /perl(\(if\)|\(deprecate\))/s;
    push @info, 'Explicit non-perl() style [build]requires, provides, obsoletes or blocks.'
        if $data =~ /(Requires|Provides|Obsoletes|Blocks):( |\t)*[^\s%]/s;
    push @info, '%{rhel} macro used.'
        if $data =~ /\%\{\??rhel\}/s;
    push @info, 'Only one type of filters used.'
        if ($data =~ /__(requires|provides)_exclude/s &&
            $data !~ /filter_from_(requires|provides)/s) ||
           ($data !~ /__(requires|provides)_exclude/s &&
            $data =~ /filter_from_(requires|provides)/s);
    push @info, 'Converting %check failed'
        unless $check;
    push @info, 'Converting %build failed'
        unless $build;
    push @info, 'Converting %install failed'
        unless $install;
    push @info, 'A perl-%{macro} style package name detected'
        if $data =~ /perl-\%/s;
    push @info, '%{license} macro used.'
        if $data =~ /\%\{?\??license\}?/s;

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
