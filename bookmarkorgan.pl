#!/usr/bin/perl
use strict;
use warnings;
use Carp;
use English '-no_match_vars';
use re '/xms';

use version; our $VERSION = qv('0.0');

use Readonly;
Readonly my $DEFAULT_BOOKMARK_DATEBASE => 'bookmarks.db';
Readonly my $EMPTY                     => q[];
Readonly my $DESCRIPTION               => <<"END"
organizes bookmarks.
END
    ;

use Getopt::Long;
use DBI;
use IO::Prompt;
use Term::Complete;

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

my @plugin_subs;

sub main {
    load_plugins();
    my $bookmark_db = DBI->connect(
        "dbi:SQLite:$bookmark_database_file",
        { RaiseError => 1, AutoCommit => 0 }
    );
    $bookmark_db->do('PRAGMA foreign_keys = ON');

    my $QUIT           = qr{\A q(?:uit)? \z}i;
    my %prompt_options = (
        -prompt => '>',
        -until  => $QUIT,
    );
    my %command_hash = (
        add    => \&add,
    );
MAIN_LOOP:
    while ( my $input = prompt(%prompt_options) ) {
        my ( $command, @args ) = split m{[ ]+}, $input;
        if ( defined $command ) {
            if ( exists $command_hash{$command} ) {
                &{ $command_hash{$command} }(@args);
            }
            else {
                print "$command is not a vaild command.\n" or croak;
            }
        }
        else {
            next MAIN_LOOP;
        }
    }

    $bookmark_db->disconnect();
    return;
}

sub add {
    my $uri = shift;
    if ( not defined $uri ) {
        $uri = prompt( -prompt => 'uri >>' );
    }
    my $title;
    my $description;
    my $tags_ref;
TEST_PLUGIN:
    for my $plugin (@plugin_subs) {
        if ( &{$plugin}( $uri, 0 ) ) {    #check if plugin accpets this uri
                #if so set $title,@tags,$description
                #to the values returned by the plugin
            ( $title, $description, $tags_ref ) = &{$plugin}($uri);
            last TEST_PLUGIN;
        }
    }

    #allow user to edit the plugins results
    #
    $title       = Complete( 'title >>',       [$title] );
    $description = Complete( 'description >>', [$description] );
    my $tag_prompt = $EMPTY;
    if ( defined $tags_ref ) {
        $tag_prompt = join ', ', @{$tags_ref};
    }
    @{$tags_ref} = split m{[ ]*,[ ]*}, Complete( 'tags >>', [$tag_prompt] );
    return;
}

sub load_plugins {
    for my $plugin ( sort glob './plugins/*.pl' ) {
        require $plugin;
        my ($plugin_sub_name) = $plugin =~ m{/([^/]+)[.]pl$ };
        no strict 'refs';
        push @plugin_subs, \&{$plugin_sub_name};
        use strict;
    }
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
