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
my $wait_timeout = 3;
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
            '04' => "HTTP/1.1 200 OK\r\nContent-Length: 15\r\n\r\nHello, world!!!",
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

                my $bytes = syswrite($client, $response, bytes::length($response), 0);

                warn("Can't send the response") if $bytes != bytes::length($response);

                #print $client $response;
                sleep(0.01);
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
    'connect_timeout' => 1,
    'request_timeout' => 3,
    'ssl' => 0,
    'sol_socket' => {},
    'sol_tcp' => {},
    'inactivity_conn_ts' => 2,
);

ok( $ua->add("/page/01.html"), "Adding the first request");
ok( $ua->add("/page/02.html"), "Adding the second request");
ok(!$ua->add("/page/03.html"), "Adding the third request");

# non-blocking requests processing
while ( $ua->not_empty() ) {
    if (my $tx = $ua->next_response) { # returns an instance of Mojo::Transaction::HTTP class
        my $res = $tx->res()->headers()->to_string();
        is($res, 'Content-Length: 10', "checking the empty response");
        $processed_slots++;
        if ($tx->req()->url() =~ m#/01\.html$#) {
            is($tx->res()->body(), '0123456789', "checking response body");
        } else {
            is($tx->res()->body(), '9876543210', "checking response body");
        }
    } else {
        # waiting for a response
    }
}

is($processed_slots, 2, "checking the amount of processed slots");

# all slots are timeouetd

$ua->refresh_connections();

ok($ua->add("/page/04.html"), "Adding the fourth request");

$processed_slots = 0;

# blocking requests processing
while (my $tx = $ua->wait_for_next_response($wait_timeout)) {
    $processed_slots++;
}

is($processed_slots, 1, "checking the amount of processed slots");

done_testing();

$server->stop();

1;
__END__
