#!/usr/bin/env perl

use File::Slurp;
use Mojolicious::Lite;
use DBI;

use v5.18;
use experimental qw/switch/;

my $token = read_file("TOKEN");
chomp $token;

my $database_file = "stuff.db";

post '/slackbot' => sub {
    my $c   = shift;
    my $t   = $c->param('token');

    if ($t ne $token) {
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
        default { return }
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
        $c->render(json => {text => "it hurts when you tease me, I don't have any data :weary:"});
        return;
    }

    # Set icon emoji to match "sucks" or "rules".
    my $emoji;
    $emoji = ':raised_hands:' if $table eq "rules";
    $emoji = ':no_good:'      if $table eq "sucks";

    if ($user eq "") {
        $c->render(json => {text => $msg, icon_emoji => $emoji, username => "stuff that $table"});
    }
    else {
        $c->render(
            json => {
                text => $msg . " _(submitted by " . $user . ")_",
                icon_emoji => $emoji,
                username => "stuff that $table"
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

    $c->render(json => {text => "I'm gently placing your message in the $table basket as we speak. I love you, " . $user . "!"});
}

sub connect_database {
    return DBI->connect("dbi:SQLite:dbname=$database_file","","");
}
