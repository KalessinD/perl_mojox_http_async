package Test::Utils;

use 5.020;
use strict;
use warnings;
use experimental qw/ signatures /;
use Exporter qw/ import /;

use Test::TCP ();
use Socket qw/ inet_aton pack_sockaddr_in AF_INET SOCK_STREAM /;

our @EXPORT      = ();
our @EXPORT_OK   = qw/ get_free_port start_server notify_parent /;
our %EXPORT_TAGS = ();

our $PPID;

sub notify_parent () {
    if ($^O ne 'MSWin32' && defined($PPID)) {
        kill('USR1', $PPID);
    }
}

sub get_free_port ($start, $end, $timeout = 0.1) {
    my $free_port;
    my $host_addr = inet_aton('localhost');
    my $proto     = getprotobyname('tcp');

    socket(my $socket, AF_INET, SOCK_STREAM, $proto) || die "socket error: $!";

    for my $port ($start .. $end) {

        my $peerAddr = pack_sockaddr_in($port, $host_addr);

        eval {
            # NB: \n required
            local $SIG{'ALRM'} = sub {die("alarmed\n");};
            Time::HiRes::alarm($timeout // 0.1);
            connect($socket, $peerAddr) || die "connect error: $!";
            Time::HiRes::alarm(0);
        };

        my $error = $@;

        Time::HiRes::alarm(0) if $error;

        my $was_alarmed = ($@ && $@ eq "alarmed\n");

        if ($!{'ECONNREFUSED'}) {
            $free_port = $port;
            last;
        }
    }

    close($socket) if ($socket);

    return $free_port;
}

sub start_server ($on_start_cb, $server_port, $attempts = 10, $wait_for_a_signal_secs = 5) {

    my $can_go_further = 0;
    my $server;

    $PPID //= $$; # PID before forking the server
    $server_port //= get_free_port(49152, 65000);

    local $SIG{'USR1'} = sub ($sig) { $can_go_further = 1; };

    while ($attempts-- > 0) {
        eval {
            $server = Test::TCP->new(
                'max_wait' => 10,
                'host'     => 'localhost',
                'listen'   => 0,
                'proto'    => 'tcp',
                'port'     => $server_port,
                'code'     => $on_start_cb
            );
        };

        my $error = $@;

        last if ! $error && $server;
        die($error) if $error && $error !~ m/(Address already in use)|(Connection refused)/;
    }

    die("Server isn't started") if ! $server;

    # just an attempt to be sure that server is started
    my $stop_waiting_ts = time() + $wait_for_a_signal_secs;
    while (1) {
        sleep(0.01);
        last if (time() < $stop_waiting_ts);
        last if $can_go_further;
    }

    return $server;
}

1;
__END__
