package BS::HTTPD;
use feature ':5.10';
use strict;
no warnings;

use Scalar::Util qw/weaken/;
use URI;
use BS::HTTPD::HTTPServer;
use BS::HTTPD::Request;

our @ISA = qw/BS::HTTPD::HTTPServer/;

=head1 NAME

BS::HTTPD - A simple lightweight event based web (application) server

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';

=head1 SYNOPSIS

    use BS::HTTPD;

    my $httpd = BS::HTTPD->new (port => 9090);

    $httpd->reg_cb (
       _ => sub {
          my ($httpd, $req) = @_;

          $req->o ("<html><body><h1>Hello World!</h1>");
          $req->o ("<a href=\"/test\">another test page</a>");
          $req->o ("</body></html>");
          $req->respond;
       },
       _test => sub {
          my ($httpd, $req) = @_;

          $req->o ("<html><body><h1>Test page</h1>");
          $req->o ("<a href=\"/\">Back to the main page</a>");
          $req->o ("</body></html>");
          $req->respond;
       },
    );

=head1 DESCRIPTION

This module provides a simple HTTPD for serving simple web application
interfaces. It's completly event based and independend from any event loop
by using the L<AnyEvent> module.

It's HTTP implementation is a bit hacky, so before using this module make sure
it works for you and the expected deployment. Feel free to improve the HTTP support
and send in patches!

I mainly wrote this module to provide a HTTP interface in L<BS>. However,
it doesn't depend on L<BS> and it can be used to extend any application
with a (simple) web interface.

The documentation is currently only the source code, but next versions of
this module will be better documented hopefully. See also the C<samples/> directory
in the L<BS::HTTPD> distribution for basic starting points.

L<BS::HTTPD> even comes with some basic AJAX framework/helper.

=head1 FEATURES

=over 4

=item * support for GET and POST requests

=item * processing of C<x-www-form-urlencoded> and C<multipart/form-data> encoded form parameters

=item * ajax helper and javascript output functions in L<BS::HTTPD::Appgets>

=item * support for chunked encoding output to the HTTP client

=back

=head1 METHODS

The L<BS::HTTPD> class inherits directly from L<BS::HTTPD::HTTPServer>
which inherits the event callback interface from L<BS::Event>.

Event callbacks can be registered via the L<BS::Event> API (see the documentation
of L<BS::Event> for details).

For a list of available events see below in the I<EVENTS> section.

=over 4

=item B<new (%args)>

This is the constructor for a L<BS::HTTPD> object.
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

   $self->{max_data} //= 10;
   $self->{cleanup_interval} //= 60;
   $self->{state} //= {};

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
      BS::HTTPD::Request->new (
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

   my (@segs) = $url->path_segments;
   my $ev = join "_", @segs;

   my @res = $self->event ('request' => $req);
   push @res, $self->event ($ev => $req);
}

=back

=head1 EVENTS

Every request goes to a specific URL. After a (GET or POST) request is
received the URL is split at the '/' characters and joined again with '_' characters.
After that the event with the name of the converted URL is invoked, this means that
if you get a request to the url '/test/bla' the even C<_test_bla> is emitted,
you can register a callback for that URL like this:

   $httpd->reg_cb (
      _test_bla => sub {
         my ($httpd, $req) = @_;

         $req->respond ([200, 'ok', { 'Content-Type' => 'text/html' }, '<h1>Test</h1>' }]);
      }
   );

The first argument to such a callback is always the L<BS::HTTPD> object itself.
The second argument (C<$req>) is the L<BS::HTTPD::Request> object for this
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
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=BS-HTTPD>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc BS::HTTPD


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=BS-HTTPD>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/BS-HTTPD>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/BS-HTTPD>

=item * Search CPAN

L<http://search.cpan.org/dist/BS-HTTPD>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of BS::HTTPD
