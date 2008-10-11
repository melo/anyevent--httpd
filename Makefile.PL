use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'AnyEvent::HTTPD',
    AUTHOR              => 'Robin Redeker <elmex@ta-sa.org>',
    VERSION_FROM        => 'lib/AnyEvent/HTTPD.pm',
    ABSTRACT_FROM       => 'lib/AnyEvent/HTTPD.pm',
    LICENSE             => 'perl',
    PL_FILES            => {},
    PREREQ_PM => {
        'AnyEvent'       => 0,
        'Test::More'     => 0,
        'HTTP::Date'     => 0,
        'Object::Event'  => 0,
        'POSIX'          => 0,
        'URI'            => 0,
        'Fcntl'          => 0,
        'CGI'            => 0,
        'AnyEvent::HTTP' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz',
                             PREOP => 'pod2text lib/AnyEvent/HTTPD.pm | tee README >$(DISTVNAME)/README; chmod -R u=rwX,go=rX . ;',
    },
    clean               => { FILES => 'AnyEvent-HTTPD-*' },
);
