package main;

use 5.020;
use warnings;
use Module::Build;

my $build = Module::Build->new(
    module_name         => 'MojoX::HTTP::Async',
    license             => 'Artistic',
    create_readme       => 1,
    configure_requires  => {
        'Module::Build' => '0.4220'
    },
    build_requires => {
        'Test::TCP' => 0,
        'Test::More' => 0,
        'Time::HiRes' => 0,
        'Socket' => 0,
        'FindBin' => 0,
        'Net::EmptyPort' => 0,
    },
    requires => {
        'perl'  => 5.020,
        'POSIX' => 0,
        'Time::HiRes' => 0,
        'Socket' => 0,
        'IO::Socket::SSL' => 2.072,
        'Fcntl' => 0,
        'Carp' => 0,
        'List::Util' => 0,
        'Mojo::Message::Request' => 0,
        'Mojo::Message::Response' => 0,
        'Mojo::Transaction::HTTP' => 0,
        'URI' => 0,
        'Errno' => 0,
        'Scalar::Util' => 0,
    },
    needs_compiler => 0,
    meta_merge     => {
        'resources' => {
            'bugtracker' => 'https://github.com/KalessinD/perl_mojox_http_async/issues',
            'repository' => 'https://github.com/KalessinD/perl_mojox_http_async',
        },
    }
);

$build->create_build_script;

1;
__END__
