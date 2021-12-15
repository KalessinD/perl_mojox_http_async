package main;

use 5.020;
use utf8;
use strict;
use warnings;
use experimental qw/ signatures /;
use bytes ();

use lib 'lib/', 't/lib';

use Test::More ('import' => [qw/ done_testing is ok use_ok like /]);
use Test::Utils qw/ start_server notify_parent IS_NOT_WIN /;

use Time::HiRes qw/ sleep /;
use Socket qw/ sockaddr_in AF_INET INADDR_ANY SOCK_STREAM /;
use Mojo::Message::Request ();
use Mojo::URL ();

my $slots = 2;
my $host = 'localhost';
my $request_timeout = 3;
my $connect_timeout = 3;
my $inactivity_timeout = 1;

BEGIN { use_ok('MojoX::HTTP::Async') };

sub on_start_cb ($port) {
    socket(my $socket, AF_INET, SOCK_STREAM, getprotobyname( 'tcp' ));

    my $client;
    my $QUEUE_LENGTH = 3;
    my $my_addr = sockaddr_in($port, INADDR_ANY);

    bind($socket, $my_addr ) or die( qq(Couldn't bind socket to port $port: $!\n));
    listen($socket, $QUEUE_LENGTH) or die( "Couldn't listen port $port: $!\n" );
    notify_parent();

    while (my $peer = accept($client, $socket)) {

        my $pid;

        if ($pid = fork()) { # parent
            sleep(0.05);
        } elsif ($pid == 0) { # child
            close($socket);
            sleep($request_timeout + 1);
            exit(0);
        } else {
            die("Can't fork: $!");
        }
    }
}


my $server = start_server(\&on_start_cb, $host);
my $ua = MojoX::HTTP::Async->new(
    'host' => $host,
    'port' => $server->port(),
    'slots' => $slots,
    'connect_timeout' => $connect_timeout,
    'request_timeout' => $request_timeout,
    'inactivity_conn_ts' => $inactivity_timeout,
);

# one slot is free and one slot is busy
ok($ua->add("/page/01.html"), "Adding the first request");

sleep($inactivity_timeout + 0.1);

my $n = $ua->refresh_connections();

is($n, 1, "Checking the amount of renewed slots");

# both slots are busy
ok($ua->add("/page/02.html"), "Adding the second request");
ok($ua->add("/page/03.html"), "Adding the third request");

sleep($inactivity_timeout + 0.1);

$n = $ua->refresh_connections();

is($n, 2, "Checking the amount of renewed slots");

# all connections are fresh
ok($ua->add("/page/04.html"), "Adding the fourth request");
ok($ua->add("/page/05.html"), "Adding the fifth request");

$n = $ua->refresh_connections();
is($n, 0, "Checking the amount of renewed slots");

# there are no expired connections
$ua->close_all();

ok($ua->add("/page/06.html"), "Adding the sixth request");
ok($ua->add("/page/07.html"), "Adding the seventh request");

sleep($inactivity_timeout * 0.5);

$n = $ua->refresh_connections();
is($n, 0, "Checking the amount of renewed slots");

done_testing();

$ua->close_all();
$server->stop();

1;
__END__
