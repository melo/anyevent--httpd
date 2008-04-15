use strict;
use warnings;
use Test::More;

# Ensure a recent version of Test::Pod::Coverage
my $min_tpc = 1.08;
eval "use Test::Pod::Coverage $min_tpc";
plan skip_all => "Test::Pod::Coverage $min_tpc required for testing POD coverage"
    if $@;

# Test::Pod::Coverage doesn't require a minimum Pod::Coverage version,
# but older versions don't recognize some common documentation styles
my $min_pc = 0.18;
eval "use Pod::Coverage $min_pc";
plan skip_all => "Pod::Coverage $min_pc required for testing POD coverage"
    if $@;

my %SPEC = (
   'AnyEvent::HTTPD' => [qw/alloc_id cleanup handle_app_req start_cleanup/],
   'AnyEvent::HTTPD::Request' => [qw/form_id is_form_submit new/],
   'AnyEvent::HTTPD::HTTPConnection' => [qr/./],
   'AnyEvent::HTTPD::HTTPServer' => [qr/./],
   'AnyEvent::HTTPD::TCPConnection' => [qr/./],
   'AnyEvent::HTTPD::TCPListener' => [qr/./],
);

my $cnt = scalar all_modules ();
plan tests => $cnt;

for my $mod (all_modules ()) {
   pod_coverage_ok ($mod, { private => $SPEC{$mod} || [] });
}
