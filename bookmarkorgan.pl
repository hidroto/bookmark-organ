#!/usr/bin/perl
use strict;
use warnings;
use Carp;
use English '-no_match_vars';
use re '/xms';

use version; our $VERSION = qv('0.0');

use Readonly;
Readonly my $DEFAULT_BOOKMARK_DATEBASE => 'bookmarks.db';
Readonly my $DESCRIPTION               => <<"END"
organizes bookmarks.
END
    ;

use Getopt::Long;
use IO::Prompt;

#option flags
my $bookmark_database_file = $DEFAULT_BOOKMARK_DATEBASE;

#
my %OPTIONS = (
    'help' => [ \&print_help, 'print this help message' ],
    'database=s' =>
        [ \$bookmark_database_file, 'sqlite database to use for bookmarks' ],
);
my $options_flag = GetOptions(
    map { ( $_, $OPTIONS{$_}->[0] ) }
        keys %OPTIONS
);

if ( not $options_flag ) {
    print_help();
}
use DBI;

sub main {
    my $bookmark_db = DBI->connect(
        "dbi:SQLite:$bookmark_database_file",
        { RaiseError => 1, AutoCommit => 0 }
    );
    $bookmark_db->do('PRAGMA foreign_keys = ON');

    my $QUIT           = qr[\A q(?:uit)? \z]ixms;
    my %prompt_options = (
        -prompt => '>',
        -until  => $QUIT,
    );
MAIN_LOOP:
    while ( my $cmd = prompt(%prompt_options) ) {
    }

    $bookmark_db->disconnect();
    return;
}

sub print_help {
    print "version $VERSION;\n" or croak 'can\'t print';
    print $DESCRIPTION or croak 'can\'t print';
    for ( sort keys %OPTIONS ) {
        print "\t$_\n", "\t" x 2, $OPTIONS{$_}->[1], "\n"
            or croak 'can\'t print';
    }
    exit;
}

main();
