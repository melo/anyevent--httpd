use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'BS::HTTPD',
    AUTHOR              => 'Robin Redeker <elmex@ta-sa.org>',
    VERSION_FROM        => 'lib/BS/HTTPD.pm',
    ABSTRACT_FROM       => 'lib/BS/HTTPD.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'HTTP::Date' => 0,
        'BS::Event'  => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'BS-HTTPD-*' },
);
