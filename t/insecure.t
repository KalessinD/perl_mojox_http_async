package main;

use 5.026;
use utf8;
use strict;
use warnings;
use experimental qw/ signatures /;
use bytes ();

use lib 'lib/';

use Test::TCP ();
use Test::More ('import' => [qw/ done_testing is ok use_ok note fail /]);

use Time::HiRes qw/ sleep /;
use Socket qw/ sockaddr_in AF_INET INADDR_ANY SOCK_STREAM SOL_SOCKET SO_REUSEADDR /;
use Net::EmptyPort qw/ empty_port /;

my $server_port = empty_port({ host => 'localhost' });
my $processed_slots = 0;
my $wait_timeout = 2;
my $request_timeout = 1.2;
my $connect_timeout = 1;
my $inactivity_timeout = 1.7;
my $server = Test::TCP->new(
    'max_wait' => 10,
    'host'     => 'localhost',
    'listen'   => 0,
    'proto'    => 'tcp',  # accept(sock, QUEUEE_LENGTH= 5)
    'port'     => $server_port,
    'code'     => sub ($port) {

        socket(my $socket, AF_INET, SOCK_STREAM, getprotobyname( 'tcp' ));
        setsockopt($socket, SOL_SOCKET, SO_REUSEADDR, 1);

        my $QUEUE_LENGTH = 3;
        my $my_addr = sockaddr_in($server_port, INADDR_ANY);

        bind($socket, $my_addr ) or die( qq(Couldn't bind socket to port $server_port: $!\n));
        listen($socket, $QUEUE_LENGTH) or die( "Couldn't listen port $server_port: $!\n" );

        my $client;
        my $default_response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n";
        my %responses_by_request_number = (
            '01' => "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\n0123456789",
            '02' => "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\n9876543210",
            '03' => $default_response,
            '04' => $default_response,
            '05' => "HTTP/1.1 200 OK\r\nContent-Length: 15\r\n\r\nHello, world!!!",
            '06' => $default_response,
            '07' => $default_response,
            '08' => $default_response,
            '09' => $default_response,
            '10' => $default_response,
        );

        while (my $peer = accept($client, $socket)) {

            my $pid;

            if ($pid = fork()) { # parent
                sleep(0.05);
            } elsif ($pid == 0) { # child
                close($socket);

                local $| = 1; # autoflush
                local $SIG{'__DIE__'} = 'DEFAULT';

                my $rh = '';
                vec($rh, fileno($client), 1) = 1;
                my ($wh, $eh) = ($rh) x 2;

                select($rh, undef, $eh, undef);

                if ( vec($eh, fileno($client), 1) != 0 ) {
                    die($!);
                    exit(0);
                }

                my $data = <$client>; # GET /page/01.html HTTP/1.1
                my ($page) = (($data // '') =~ m#^[A-Z]{3,}\s/page/([0-9]+)\.html#);
                my $response = $default_response;

                $response = $responses_by_request_number{$page} // $response if $page;

                $eh = $wh;

                select(undef, $wh, $eh, undef);

                if ( vec($eh, fileno($client), 1) != 0 ) {
                    die($!);
                    exit(0);
                }

                if ($page && ($page eq '06' || $page eq '07' || $page eq '08')) { # tests for request timeouts
                    sleep($request_timeout + 0.1);
                }

                my $bytes = syswrite($client, $response, bytes::length($response), 0);

                warn("Can't send the response") if $bytes != bytes::length($response);

                sleep(0.1);
                close($client);
                exit(0);
            } else {
                die("Can't fork: $!");
            }
        }
    },
);

BEGIN { use_ok('MojoX::HTTP::Async') };

my $ua = MojoX::HTTP::Async->new(
    'host' => 'localhost',
    'port' => $server->port(),
    'slots' => 2,
    'connect_timeout' => $connect_timeout,
    'request_timeout' => $request_timeout,
    'ssl' => 0,
    'sol_socket' => {},
    'sol_tcp' => {},
    'inactivity_conn_ts' => $inactivity_timeout,
);

ok( $ua->add("/page/01.html"), "Adding the first request");
ok( $ua->add("/page/02.html"), "Adding the second request");
ok(!$ua->add("/page/03.html"), "Adding the third request");

# non-blocking requests processing
while ( $ua->not_empty() ) {
    if (my $tx = $ua->next_response) { # returns an instance of Mojo::Transaction::HTTP class
        my $res = $tx->res();
        $processed_slots++;
        is($res->headers()->to_string(), 'Content-Length: 10', "checking the response headers");
        is($res->code(), '200', 'checking the response code');
        is($res->message(), 'OK', 'checking the response message');
        if ($tx->req()->url() =~ m#/01\.html$#) {
            is($res->body(), '0123456789', "checking response body");
        } else {
            is($res->body(), '9876543210', "checking response body");
        }
    } else {
        # waiting for a response
    }
}

is($processed_slots, 2, "checking the amount of processed slots");

# all connections were closed in Test::TCP after the response is sent
# but we don't know about this, so our new request will be timeouted

ok($ua->add("/page/04.html"), "Adding the fourth request");

$processed_slots = 0;

# blocking requests processing
while (my $tx = $ua->wait_for_next_response($wait_timeout)) {
    $processed_slots++;
    my $res = $tx->res();
    is($res->body(), '', "checking response body");
    is($res->message(), 'Request timeout', 'checking the response message');
    is($res->code(), '524', 'checking the response code');
}

is($processed_slots, 1, "checking the amount of processed slots");

$ua->close_all();

$processed_slots = 0;

# one slot is OK, one slot is time-outed

ok($ua->add("/page/05.html"), "Adding the fifth request");
ok($ua->add("/page/06.html"), "Adding the sixth request");

while (my $tx = $ua->wait_for_next_response($wait_timeout)) {
    $processed_slots++;
    my $res = $tx->res();
    if ($tx->req()->url() =~ m#/05\.html$#) {
        is($res->body(), 'Hello, world!!!', "checking response body");
        is($res->message(), 'OK', 'checking the response message');
    } else {
        is($res->body(), '', "checking response body");
        is($res->message(), 'Request timeout', 'checking the response message');
    }
}

is($processed_slots, 2, "checking the amount of processed slots");

$ua->close_all();

$processed_slots = 0;

# all slots are timeouted

ok($ua->add("/page/07.html"), "Adding the seventh request");
ok($ua->add("/page/08.html"), "Adding the eight request");

while (my $tx = $ua->wait_for_next_response($wait_timeout)) {
    $processed_slots++;
    my $res = $tx->res();
    is($res->body(), '', "checking response body");
    is($res->message(), 'Request timeout', 'checking the response message');
}

is($processed_slots, 2, "checking the amount of processed slots");

ok(! $ua->add("/page/09.html"), "Adding the nineth request");

# let's cleanup timeouted connections

$processed_slots = 0;

$ua->refresh_connections();

ok($ua->add("/page/10.html"), "Adding the eight request");

while (my $tx = $ua->wait_for_next_response($wait_timeout)) {
    $processed_slots++;
}

is($processed_slots, 1, "checking the amount of processed slots");

done_testing();

$server->stop();

1;
__END__