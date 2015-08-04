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
Readonly my $BOOKMARKS_SQL_TEMPLATE => <<"END"
PRAGMA foreign_keys=ON;
BEGIN TRANSACTION;
CREATE TABLE "tags" (
	`TAG_id`	INTEGER NOT NULL,
	`TAG_phrase`	TEXT NOT NULL UNIQUE,
	PRIMARY KEY(TAG_id)
);
CREATE TABLE "LINK_bookmark_tag" (
	`BKM_id`	INTEGER NOT NULL,
	`TAG_id`	INTEGER NOT NULL,
	FOREIGN KEY(`BKM_id`) REFERENCES bookmarks ( BKM_id ),
	FOREIGN KEY(`TAG_id`) REFERENCES tags ( TAG_id )
);
CREATE TABLE "bookmarks" (
	`BKM_id`	INTEGER NOT NULL,
	`BKM_title`	TEXT NOT NULL,
	`BKM_uri`	TEXT NOT NULL UNIQUE,
	PRIMARY KEY(BKM_id)
);
CREATE TRIGGER delete_TAG delete on tags
begin
    delete from LINK_bookmark_tag where OLD.TAG_id == LINK_bookmark_tag.TAG_id;
end;
CREATE TRIGGER delete_BKM delete on bookmarks
begin
    delete from LINK_bookmark_tag where OLD.BKM_id == LINK_bookmark_tag.BKM_id;
end;
CREATE TRIGGER no_same_row_LINK before insert on LINK_bookmark_tag
begin
delete from LINK_bookmark_tag where NEW.BKM_id == LINK_bookmark_tag.BKM_id and NEW.TAG_id == LINK_bookmark_tag.TAG_id;
end;
COMMIT;
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
    my $bookmark_db = load_database();

    my $QUIT = qr{\A q(?:uit)? \z}i;
    my %command_hash = (
        add => \&add,
    );
MAIN_LOOP:
    while ( my $input = prompt( '>', { -until => $QUIT } ) ) {
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

sub load_database {
    my $db = DBI->connect(
        "dbi:SQLite:$bookmark_database_file",
        { RaiseError => 1, AutoCommit => 0 }
    );
    $db->do('PRAGMA foreign_keys = ON');
    return $db;
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
