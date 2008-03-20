#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'BS::HTTPD' );
}

diag( "Testing BS::HTTPD $BS::HTTPD::VERSION, Perl $], $^X" );
