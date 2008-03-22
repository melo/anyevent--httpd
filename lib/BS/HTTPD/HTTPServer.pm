package BS::HTTPD::HTTPServer;
use feature ':5.10';
use strict;
no warnings;

use BS::HTTPD::TCPListener;
use BS::HTTPD::HTTPConnection;

=head1 NAME

BS::HTTPD::HTTPServer - A simple and plain http server

=head1 DESCRIPTION

This class handles incoming TCP connections for HTTP clients.
It's used by L<BS::HTTPD> to do it's job.

It has no public interface yet.

=head1 COPYRIGHT & LICENSE

Copyright 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

our @ISA = qw/BS::HTTPD::TCPListener/;

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

sub connection_class { 'BS::HTTPD::HTTPConnection' }

1;
