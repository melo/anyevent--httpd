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

my $t = AnyEvent->timer (after => 0.5, cb => sub {
  http_get "http://127.0.0.1:19090/test", sub {
    $content = $_[0];
    $h->stop;
  };
});

$h->run;

is($req_url,  "/test", "the path of the request URL was ok");
is($req_url2, "/test", "the path of the second request URL was ok");
is($req_method, 'GET', 'Correct method used');
is($content,  'Test response', "the response text was ok");
