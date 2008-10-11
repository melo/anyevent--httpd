#!perl
use strict;
use Test::More tests => 10;
use AnyEvent::HTTPD;
use AnyEvent::HTTP;

my $h = AnyEvent::HTTPD->new (port => 19090);
ok($h);

my $req_url;
my $req_url2;
my $req_method;
my $content;
my @params;
my %params;

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
  
  {
    request => [ \&http_get, 'http://127.0.0.1:19090/get?q=%3F%3F&n=%3F%3F' ],
    result  => sub {
      is(scalar(@params), 2, 'Two parameters');
      is($params{q}, '??', "Proper escaped param 'q'");
      is($params{n}, '??', "Proper escaped param 'n'");
      is($params{raw_n}, '%3F%3F', "Proper raw escaped param 'n'");
      ok(!defined($req_url), 'Request stoped at most specific handler');
    },
  }
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
   
   '/get' => sub {
      my ($httpd, $req) = @_;
      
      @params = $req->params;
      foreach my $p (@params) {
        $params{$p} = $req->param($p);
        $params{"raw_$p"} = $req->parm($p);
      }
      
      my $method = $req->method;
      $req->respond ({content => ['text/plain', "Ok $method"]});
      $httpd->stop_request;
   },
);

my $t = AnyEvent->timer (after => 0.5, cb => \&run_next_test);
$h->run;

my $current_test;
sub run_next_test {
  $current_test ||= 0;

  ($req_url, $req_url2, $req_method, $content) = ();
  %params = @params = ();
  
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

