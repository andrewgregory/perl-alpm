#!/usr/bin/perl

use strict;
use warnings;

our $VERSION = 'v0.0.1';

use ALPM;
use Data::Dumper;
use PacUtils::Config;

my $alpm = parse_config('/etc/pacman.conf');
my ($op, $pkg) = @ARGV;

$alpm->set_eventcb(\&eventcb);
$alpm->trans_init({});

if($op eq 'install') {
    $pkg = findpkg($alpm, $pkg) or die "could not locate pkg";
    $alpm->add_pkg($pkg);
} elsif($op eq 'remove') {
    $pkg = $alpm->localdb->find($pkg) or die "could not locate pkg";
    $alpm->remove_pkg($pkg);
} else {
    die "unknown op $op";
}

$alpm->trans_prepare;
$alpm->trans_commit;
$alpm->trans_release;

sub parse_config {
    my ($file) = @_;
    my $conf = PacUtils::Config::load('/etc/pacman.conf');
    my $alpm = ALPM->new($conf->{rootdir}, $conf->{dbpath});
    $alpm->set_logfile($conf->{logfile});
    foreach my $repo (@{ $conf->{repository} }) {
        my $db = $alpm->register($repo->{name});
        $db->add_server($_) foreach @{ $repo->{server} };
    }
    return $alpm;
}

sub eventcb {
    my ($ev) = @_;
    print Dumper($ev);
    return;
}

sub findpkg {
    my ($a, $pkgname) = @_;
    foreach my $db ( $a->syncdbs ) {
        my $p = $db->find($pkgname) or next;
        return $p;
    }
    return undef;
}
