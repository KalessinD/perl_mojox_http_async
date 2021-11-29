package Test::SockUtils;

use 5.026;
use strict;
use warnings;
use experimental qw/ signatures /;
use Exporter qw/ import /;

use Socket qw/ inet_aton pack_sockaddr_in AF_INET SOCK_STREAM /;

our @EXPORT      = ();
our @EXPORT_OK   = qw/ get_free_port /;
our %EXPORT_TAGS = ();

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

1;
__END__
