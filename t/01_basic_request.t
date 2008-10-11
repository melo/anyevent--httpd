#!perl
use strict;
use Test::More tests => 5;
use AnyEvent::HTTPD;
use AnyEvent::HTTP;

my $h = AnyEvent::HTTPD->new (port => 19090);
ok($h);

my $req_url;
my $req_url2;
my $req_method;
my $content;

my @tests = (
  {
    request => [ \&http_get, 'http://127.0.0.1:19090/test' ],
    result  => sub {
      is($req_url,  "/test", "the path of the request URL was ok");
      is($req_url2, "/test", "the path of the second request URL was ok");
      is($req_method, 'GET', 'Correct method used');
      is($_[0], 'Test response', "the response text was ok");
    },
  },
);


$h->reg_cb (
   '' => sub {
      my ($httpd, $req) = @_;
      $req_url = $req->url->path;
   },
   '/test' => sub {
      my ($httpd, $req) = @_;
      $req_url2 = $req->url->path;
      $req_method = $req->method;
      $req->respond ({content => ['text/plain', "Test response"]});
   },
);

my $t = AnyEvent->timer (after => 0.5, cb => \&run_next_test);
$h->run;

my $current_test;
sub run_next_test {
  $current_test ||= 0;

  my $test = $tests[$current_test++];
  if (!$test) {
    $h->stop;
    return;
  }
  
  my $request = $test->{request};
  my $result  = $test->{result};
  
  my ($f, @args) = @$request;
    
  $f->(@args, sub {
    $result->(@_);
    run_next_test();
  });
}

