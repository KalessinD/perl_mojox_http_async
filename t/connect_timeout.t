package main;

use 5.020;
use utf8;
use strict;
use warnings;
use experimental qw/ signatures /;

use lib 'lib/', 't/lib';

use Socket qw/ AF_INET SOCK_STREAM INADDR_ANY sockaddr_in /;

use Test::More ('import' => [qw/ done_testing is ok use_ok /]);
use Test::Utils qw/ start_server notify_parent /;

my $host = 'localhost';
my $connect_timeout = 3;

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
    'slots' => 1,
    'connect_timeout' => $connect_timeout,
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
