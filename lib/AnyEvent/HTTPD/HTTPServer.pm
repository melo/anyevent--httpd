package AnyEvent::HTTPD::HTTPServer;
use strict;
no warnings;

use AnyEvent::HTTPD::TCPListener;
use AnyEvent::HTTPD::HTTPConnection;

=head1 NAME

AnyEvent::HTTPD::HTTPServer - A simple and plain http server

=head1 DESCRIPTION

This class handles incoming TCP connections for HTTP clients.
It's used by L<AnyEvent::HTTPD> to do it's job.

It has no public interface yet.

=head1 COPYRIGHT & LICENSE

Copyright 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

our @ISA = qw/AnyEvent::HTTPD::TCPListener/;

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self = $class->SUPER::new (@_);

   $self->reg_cb (
      connect => sub {
         my ($list, $cl) = @_;
      },
      disconnect => sub {
         my ($list, $cl) = @_;
      }
   );

   return $self
}

sub connection_class { 'AnyEvent::HTTPD::HTTPConnection' }

1;
