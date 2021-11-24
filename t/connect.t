package main;

use utf8;
use strict;
use warnings;

use lib 'lib/';

use Test::TCP ();
use Test::More ('import' => [qw/ done_testing is ok use_ok note fail /]);

my $processed_slots = 0;
my $wait_timeout = 3;
my $server;

{
    $server = Test::TCP->new(
        'listen' => 1,
        'code' => sub {
            my $socket = shift;
            my $rh = '';

            vec($rh, fileno($socket), 1) = 1;

            my ($wh, $eh) = ($rh) x 2;

            while (1) {
                # IDK how to get and send response here yet
                #select($rh, undef, undef, undef);
                #my $data = <$socket>;
                #select(undef, $wh, $eh, undef);
                #note($!);
                #if ( vec($error_handles, $slot_no, 1) != 0 )
                #$socket->print("test");
                #$socket->flush();
                sleep(1);
            }
        },
    );
}

BEGIN { use_ok('MojoX::HTTP::Async') };

my $ua = MojoX::HTTP::Async->new(
    'host' => 'localhost',
    'port' => $server->port(),
    'slots' => 2,
    'connect_timeout' => 1,
    'request_timeout' => 2,
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
        is($res, 'Content-Length: 0', "checking the empty response");
        $processed_slots++;
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

1;
__END__
