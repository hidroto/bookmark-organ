#!/usr/bin/perl
use strict;
use warnings;
use Carp;
use English '-no_match_vars';
use re '/xms';
use autodie;

use version; our $VERSION = qv('0.0');

use Readonly;
Readonly my $DEFAULT_BOOKMARK_DATEBASE => 'bookmarks.db';
Readonly my $EMPTY                     => q[];
Readonly my $DOT                       => q[.];
Readonly my $INPUT_PIPE_MODE           => q[|-];
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
my $bookmark_db;

#sql statments
#these act like subroutines for the datebase.
my $add_bookmark = q[INSERT INTO bookmarks (BKM_title,BKM_uri) values (?,?);];
my $add_tag = q[INSERT INTO LINK_bookmark_tag (TAG_id,BKM_id) values (?,?);];
my $get_bkm_id = q[SELECT BKM_id FROM bookmarks WHERE BKM_uri == ?;];
my $get_tag_id = q[SELECT TAG_id FROM tags WHERE TAG_phrase==?;];
my $insert_tag = q[INSERT INTO tags (TAG_phrase) values (?);];
my $select_bookmarks_by_title = q[SELECT BKM_title,BKM_uri from bookmarks;];
my $select_tags               = q[SELECT TAG_phrase from tags;];

sub main {
    load_plugins();
    $bookmark_db = load_database($bookmark_database_file);
    prepare_sql_statements();

    my $QUIT = qr{\A q(?:uit)? \z}i;
    my %command_hash;
    %command_hash = (
        add    => [ \&add, 'adds a uri to the bookmarks database' ],
        import => [
            \&import_from_file,
            'adds all of the uris in the listed file to the datebase'
        ],
        list => [ \&list,      'list all the bookmarks by title and uri' ],
        tags => [ \&list_tags, 'list all of the tags in the datebase' ],
        help => [
            sub {
                for ( sort keys %command_hash ) {
                    print $_, "\t", $command_hash{$_}->[1], "\n";
                }
                return;
            },
            'print help of the commands'
        ],
    );
MAIN_LOOP:
    while ( my $input = prompt( '>', { -until => $QUIT } ) ) {
        my ( $command, @args ) = split m{[ ]+}, $input;
        if ( defined $command ) {
            if ( exists $command_hash{$command} ) {
                &{ $command_hash{$command}->[0] }(@args);
            }
            else {
                print "$command is not a vaild command.\n" or croak;
                &{ $command_hash{help}->[0] };
            }
        }
        else {
            next MAIN_LOOP;
        }
    }

    finish_sql_statements();
    $bookmark_db->disconnect();
    return;
}

sub add {
    my $uri = shift;
    if ( not defined $uri ) {
        return;
    }
    $get_bkm_id->execute($uri);
    if ( $get_bkm_id->fetchrow_array() ) {
        print
            "'$uri' already in database\nuse edit to change uri info or remove to remove it.\n"
            or carp 'could not print';
        return;
    }
    my $title;
    my $description;
    my $tags_ref;
    my $plugin_fits;
TEST_PLUGIN:
    for my $plugin (@plugin_subs) {
        if ( $plugin_fits = &{$plugin}( $uri, 0 ) )
        {    #check if plugin accpets this uri
             #set $title,@tags,$description to the values returned by the plugin
            ( $title, $description, $tags_ref ) = &{$plugin}($uri);
            last TEST_PLUGIN;
        }
    }
    if ( not $plugin_fits ) {
        return;
    }
    chomp $title;
    chomp $uri;

    $add_bookmark->execute( $title, $uri );
    $get_bkm_id->execute($uri);
    my $bkm_id = ( $get_bkm_id->fetchrow_array() )[0];

    for my $tag ( @{$tags_ref} ) {
        chomp $tag;
        my $tag_id;
        $get_tag_id->execute($tag);
        if ( not $tag_id = ( $get_tag_id->fetchrow_array() )[0] ) {
            $insert_tag->execute($tag);
            $get_tag_id->execute($tag);
            $tag_id = ( $get_tag_id->fetchrow_array() )[0];
        }
        $add_tag->execute( $tag_id, $bkm_id );
    }
    return;
}

sub list {
    $select_bookmarks_by_title->execute();
    while ( my @row = $select_bookmarks_by_title->fetchrow_array() ) {
        print "$row[0]\n\t$row[1]\n" or carp 'could not print';
    }
    return;
}

sub import_from_file {
    my $filename = shift;
    if ( not -e $filename ) {
        return 0;
    }
    open my $uri_file_handle, '<', $filename;
    while ( my $uri = <$uri_file_handle> ) {
        add($uri);
        print $DOT;
    }
    print "\n";
    close $uri_file_handle;
    return;
}

sub list_tags {
    $select_tags->execute();
    my $tags_ref = $select_tags->fetchall_arrayref();
    for ( @{$tags_ref} ) {
        print $_->[0];
        print "\n";
    }
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
    my $db_filename = shift;
    if ( not -e $db_filename ) {
        open my $fh, $INPUT_PIPE_MODE, qq{sqlite3 $db_filename}
            or croak "could not create $db_filename";
        print {$fh} $BOOKMARKS_SQL_TEMPLATE
            or croak "could not create $db_filename from SQL_TEMPLATE";
        close $fh or croak 'could not close sqlite filehandle';
    }
    my $db = DBI->connect( "dbi:SQLite:$db_filename",
        { RaiseError => 1, AutoCommit => 0 } );
    $db->do('PRAGMA foreign_keys = ON');
    return $db;
}

sub prepare_sql_statements {
    $add_bookmark = $bookmark_db->prepare($add_bookmark);
    $add_tag      = $bookmark_db->prepare($add_tag);
    $get_bkm_id   = $bookmark_db->prepare($get_bkm_id);
    $get_tag_id   = $bookmark_db->prepare($get_tag_id);
    $insert_tag   = $bookmark_db->prepare($insert_tag);
    $select_bookmarks_by_title
        = $bookmark_db->prepare($select_bookmarks_by_title);
    $select_tags = $bookmark_db->prepare($select_tags);
    return;
}

sub finish_sql_statements {
    $add_bookmark->finish();
    $add_tag->finish();
    $get_bkm_id->finish();
    $get_tag_id->finish();
    $insert_tag->finish();
    $select_bookmarks_by_title->finish();
    $select_tags->finish();
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
