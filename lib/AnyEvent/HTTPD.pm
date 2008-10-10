package AnyEvent::HTTPD;
use strict;
no warnings;

use Scalar::Util qw/weaken/;
use URI;
use AnyEvent::HTTPD::HTTPServer;
use AnyEvent::HTTPD::Request;

our @ISA = qw/AnyEvent::HTTPD::HTTPServer/;

=head1 NAME

AnyEvent::HTTPD - A simple lightweight event based web (application) server

=head1 VERSION

Version 0.04

=cut

our $VERSION = '0.04';

=head1 SYNOPSIS

    use AnyEvent::HTTPD;

    my $httpd = AnyEvent::HTTPD->new (port => 9090);

    $httpd->reg_cb (
       '/' => sub {
          my ($httpd, $req) = @_;

          $req->o ("<html><body><h1>Hello World!</h1>");
          $req->o ("<a href=\"/test\">another test page</a>");
          $req->o ("</body></html>");
          $req->respond;
       },
       '/test' => sub {
          my ($httpd, $req) = @_;

          $req->o ("<html><body><h1>Test page</h1>");
          $req->o ("<a href=\"/\">Back to the main page</a>");
          $req->o ("</body></html>");
          $req->respond;
       },
    );

    $httpd->run; # making a AnyEvent condition variable would also work

=head1 DESCRIPTION

This module provides a simple HTTPD for serving simple web application
interfaces. It's completly event based and independend from any event loop
by using the L<AnyEvent> module.

It's HTTP implementation is a bit hacky, so before using this module make sure
it works for you and the expected deployment. Feel free to improve the HTTP support
and send in patches!

The documentation is currently only the source code, but next versions of
this module will be better documented hopefully. See also the C<samples/> directory
in the L<AnyEvent::HTTPD> distribution for basic starting points.

L<AnyEvent::HTTPD> even comes with some basic AJAX framework/helper.

=head1 FEATURES

=over 4

=item * support for GET and POST requests

=item * processing of C<x-www-form-urlencoded> and C<multipart/form-data> encoded form parameters

=item * ajax helper and javascript output functions in L<AnyEvent::HTTPD::Appgets>

=item * support for chunked encoding output to the HTTP client

=back

=head1 METHODS

The L<AnyEvent::HTTPD> class inherits directly from L<AnyEvent::HTTPD::HTTPServer>
which inherits the event callback interface from L<Object::Event>.

Event callbacks can be registered via the L<Object::Event> API (see the documentation
of L<Object::Event> for details).

For a list of available events see below in the I<EVENTS> section.

=over 4

=item B<new (%args)>

This is the constructor for a L<AnyEvent::HTTPD> object.
The C<%args> hash may contain one of these key/value pairs:

=over 4

=item port => $port

The TCP port the HTTP server will listen on.

=back

=cut

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = $class->SUPER::new (@_);

   $self->start_cleanup;

   $self->reg_cb (
      connect => sub {
         my ($self, $con) = @_;

         $self->{conns}->{$con} = $con->reg_cb (
            request => sub {
               my ($con, $meth, $url, $hdr, $cont) = @_;
               #d# warn "REQUEST: $meth, $url, [$cont] " . join (',', %$hdr) . "\n";

               $url = URI->new ($url);

               if ($meth eq 'GET') {
                  $cont = $con->parse_urlencoded ($url->query);
               }

               if ($meth eq 'GET' or $meth eq 'POST') {

                  weaken $con;
                  $self->handle_app_req ($url, $hdr, $cont, sub {
                     $con->response (@_) if $con;
                  });
               } else {
                  $con->response (200, "ok");
               }
            }
         );
      },
      disconnect => sub {
         my ($self, $con) = @_;
         $con->unreg_cb (delete $self->{conns}->{$con});
      }
   );

   $self->{max_data} 
      = defined $self->{max_data} ? $self->{max_data} : 10;
   $self->{cleanup_interval}
      = defined $self->{cleanup_interval} ? $self->{cleanup_interval} : 60;
   $self->{state} ||= {};

   return $self
}

sub start_cleanup {
   my ($self) = @_;
   $self->{clean_tmr} =
      AnyEvent->timer (after => $self->{cleanup_interval}, cb => sub {
         $self->cleanup;
         $self->start_cleanup;
      });
}

sub cleanup {
   my ($self) = @_;

   my $cnt = scalar @{$self->{form_ages} || []};

   if ($cnt > $self->{max_data}) {
      my $diff = $cnt - $self->{max_data};

      while ($cnt-- > 0) {
         my $d = pop @{$self->{form_ages} || []};
         last unless defined $d;
         delete $self->{form_cbs}->{$d->[1]};
      }
   }
}

sub alloc_id {
   my ($self, $dest, @args) = @_;
   $self->{form_id}++;
   $self->{form_cbs}->{"$self->{form_id}"} = [$dest, \@args];
   push @{$self->{form_ages}}, [time, $self->{form_id}];
   $self->{form_id}
}

sub handle_app_req {
   my ($self, $url, $hdr, $cont, $respcb) = @_;

   weaken $self;

   my $req =
      AnyEvent::HTTPD::Request->new (
         httpd   => $self,
         url     => $url,
         hdr     => $hdr,
         parm    => (ref $cont ? $cont : {}),
         content => (ref $cont ? undef : $cont),
         resp    => $respcb
      );

   if ($req->is_form_submit) {
      my $id = $req->form_id;
      my $cb = $self->{form_cbs}->{"$id"};

      if (ref $cb->[0] eq 'CODE') {
         $cb->[0]->($req);
      }
   }

   $self->event ('request' => $req);

   my @evs;
   my $cururl = '';
   for my $seg ($url->path_segments) {
      $cururl .= $seg;
      push @evs, $cururl;
      $cururl .= '/';
   }

   $self->{req_stop} = 0;
   for my $ev (reverse @evs) {
      $self->event ($ev => $req);
      last if $self->{req_stop};
   }
}

=item B<stop_request>

When the server walks the request URI path upwards you can stop
the walk by calling this method. Example:

   $httpd->reg_cb (
      '/test' => sub {
         my ($httpd, $req) = @_;

         # ...

         $httpd->stop_request; # will prevent that the callback below is called
      },
      '' => sub { # this one wont be called by a request to '/test'
         my ($httpd, $req) = @_;

         # ...
      }
   );

=cut

sub stop_request {
   my ($self) = @_;
   $self->{req_stop} = 1;
}

=item B<run>

This method is a simplification of the C<AnyEvent> condition variable
idiom. You can use it instead of writing:

   my $cvar = AnyEvent->condvar;
   $cvar->wait;

=cut

sub run {
   my ($self) = @_;
   $self->{condvar} = AnyEvent->condvar;
   $self->{condvar}->wait;
}

=item B<stop>

This will stop the HTTP server and return from the
C<run> method B<if you started the server via that method!>

=cut

sub stop { $_[0]->{condvar}->broadcast if $_[0]->{condvar} }

=back

=head1 EVENTS

Every request goes to a specific URL. After a (GET or POST) request is
received the URL's path segments are walked down and for each segment
a event is generated. An example:

If the URL '/test/bla.jpg' is requestes following events will be generated:

  '/test/bla.jpg' - the event for the last segment
  '/test'         - the event for the 'test' segment
  ''              - the root event of each request

To actually handle any request you just have to register a callback for the event
name with the empty string. To handle all requests in the '/test' directory
you have to register a callback for the event with the name C<'/test'>.
Here is an example how to register an event for the example URL above:

   $httpd->reg_cb (
      '/test/bla.jpg' => sub {
         my ($httpd, $req) = @_;

         $req->respond ([200, 'ok', { 'Content-Type' => 'text/html' }, '<h1>Test</h1>' }]);
      }
   );

See also C<stop_request> about stopping the walk of the path segments.

The first argument to such a callback is always the L<AnyEvent::HTTPD> object itself.
The second argument (C<$req>) is the L<AnyEvent::HTTPD::Request> object for this
request. It can be used to get the (possible) form parameters for this
request or the transmitted content and respond to the request.

Also every request also emits the C<request> event, with the same arguments and semantics,
you can use this to implement your own request multiplexing.

=head1 CACHING

Any response from the HTTP server will have C<Cache-Control> set to C<max-age=0> and
also the C<Expires> header set to the C<Date> header. Meaning: Caching is disabled.

If you need caching or would like to have it you can send me a mail or even
better: a patch :)

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-bs-httpd at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=AnyEvent-HTTPD>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc AnyEvent::HTTPD


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=AnyEvent-HTTPD>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/AnyEvent-HTTPD>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/AnyEvent-HTTPD>

=item * Search CPAN

L<http://search.cpan.org/dist/AnyEvent-HTTPD>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of AnyEvent::HTTPD
