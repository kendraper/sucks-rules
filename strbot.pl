#!/usr/bin/env perl

use File::Slurp;
use Mojolicious::Lite;
use DBI;

use v5.18;
use experimental qw/smartmatch switch/;

my @tokens = map { chomp; $_ } read_file("TOKENS");

my $database_file = "stuff.db";

post '/slackbot' => sub {
    my $c = shift;
    my $t = $c->param('token');

    unless ($t ~~ @tokens) {
        $c->render(text => 'denied',status => 403);
        return;
    }

    main_handler($c);
};

app->start;

use subs qw/random_sucks random_rules/;

sub main_handler {
    my $c = shift;

    my $trigger = $c->param('trigger_word');
    my $text    = $c->param('text');
    my $channel = $c->param('channel_name');
    my $domain  = $c->param('team_domain');
    my $user    = $c->param('user_name');

    # New: support for a slash command.
    my $command = $c->param('command');
    
    # Remove leading trigger and whitespace from sts/str text.
    # Do not assume $trigger is safe, substitute only known trigger words.
    my @triggers = qw(sts- sts: str- str:);
    for (@triggers) {
        $text =~ s{^\Q$_}{}i;
    }

    $text =~ s/^\s+|\s+$//;

    given ($trigger) {
        when (/^sucks\?/i)  { random_sucks($c) }
        when (/^rules\?/i)  { random_rules($c) }
        when (/^sts[:\-]/i) {
            add_sucks($c, $text, $channel, $domain, $user);
        }
        when (/^str[:\-]/i) {
            add_rules($c, $text, $channel, $domain, $user);
        }
    }

    # TODO:
    # NOTIMPLEMENTED: /sts and /str slash commands (different integration)
    given ($command) {
        when (m{^/sts}i) {
            $c->render(
                text => "Ooh, fancy! A slash command for stuff that sucks!",
            );
        }
        when (m{^/str}i) {
            $c->render(
                text => "Ooh, fancy! A slash command for stuff that rules!",
            );
        }
    }
}

sub random_sucks {
    say_random("sucks", shift);
}

sub random_rules {
    say_random("rules", shift);
}

sub say_random {
    my $table = shift;
    my $c = shift;

    my $dbh = connect_database();
    my $sth = $dbh->prepare("
        SELECT msg, user FROM $table ORDER BY RANDOM() LIMIT 1
    ");

    $sth->execute();
    my ($msg, $user) = $sth->fetchrow_array();

    if ($msg eq "") {
        $c->render(
            json => {
                text => "it hurts when you tease me, I don't have any data :weary:",
            }
        );
        return;
    }

    # Set icon emoji to match "sucks" or "rules".
    my $emoji;
    $emoji = ':+1:' if $table eq "rules";
    $emoji = ':no_good:'      if $table eq "sucks";

    if ($user eq "") {
        $c->render(
            json => {
                text => $msg,
                icon_emoji => $emoji,
                username => "stuff that $table",
            }
        );
    }
    else {
        $c->render(
            json => {
                text => $msg . " _(submitted by " . $user . ")_",
                icon_emoji => $emoji,
                username => "stuff that $table",
            }
        );
    }

}

sub add_sucks {
    insert_record("sucks", @_);
}

sub add_rules {
    insert_record("rules", @_);
}

sub insert_record {
    my ($table, $c, $text, $channel, $domain, $user) = @_;

    my $dbh = connect_database();

    my $sth = $dbh->prepare("
        INSERT INTO $table (msg, user, channel, domain, date)
        VALUES (?, ?, ?, ?, datetime('now'))
    ");

    $sth->execute($text, $user, $channel, $domain);

    $dbh->commit;
    $dbh->disconnect;

    $c->render(
        json => {
            text => "You know what? I think that $table, too! Saved.",
        }
    );
}

sub connect_database {
    return DBI->connect("dbi:SQLite:dbname=$database_file","","");
}
