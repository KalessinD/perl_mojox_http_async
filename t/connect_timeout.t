package main;

use 5.020;
use utf8;
use strict;
use warnings;
use experimental qw/ signatures /;
use bytes ();

use lib 'lib/', 't/lib';

use Test::More ('import' => [qw/ done_testing is ok use_ok note like /]);
use Test::Utils qw/ start_server notify_parent IS_NOT_WIN /;

use Time::HiRes qw/ sleep /;
use Socket qw/ sockaddr_in AF_INET INADDR_ANY SOCK_STREAM /;
use Mojo::Message::Request ();
use Mojo::URL ();

my $host = 'localhost';
my $wait_timeout = 2;
my $request_timeout = 1.5;
my $connect_timeout = 3;
my $inactivity_timeout = 1.1;

BEGIN { use_ok('MojoX::HTTP::Async') };

sub on_start_cb ($port) {
    socket(my $socket, AF_INET, SOCK_STREAM, getprotobyname( 'tcp' ));

    my $QUEUE_LENGTH = 3;
    my $my_addr = sockaddr_in($port, INADDR_ANY);

    bind($socket, $my_addr ) or die( qq(Couldn't bind socket to port $port: $!\n));
    listen($socket, $QUEUE_LENGTH) or die( "Couldn't listen port $port: $!\n" );

    notify_parent();

    sleep($connect_timeout + 3);
}


my $server = start_server(\&on_start_cb, $host);
my $ua = MojoX::HTTP::Async->new(
    'host' => $host,
    'port' => $server->port(),
    'slots' => 2,
    'connect_timeout' => $connect_timeout,
    'request_timeout' => $request_timeout,
    'ssl' => 0,
    'inactivity_conn_ts' => $inactivity_timeout,
    &IS_NOT_WIN() ? (
        'sol_socket' => {'so_keepalive' => 1},
        'sol_tcp' => {
            'tcp_keepidle' => 15,
            'tcp_keepintvl' => 3,
            'tcp_keepcnt' => 2,
        }
    ) : (),
);

ok($ua->add("/page/01.html"), "Adding the first request");

# non-blocking requests processing
while ( $ua->not_empty() ) {
    if (my $tx = $ua->next_response) { # returns an instance of Mojo::Transaction::HTTP class
        my $res = $tx->res();
        is($res->headers()->to_string(), 'Content-Length: 0', "checking the response headers");
        is($res->code(), '524', 'checking the response code');
        is($res->message(), 'Request timeout', 'checking the response message');
        is($res->body(), '', "checking the response body");
    } else {
        # waiting for a response
    }
}

done_testing();

$server->stop();

1;
__END__
