package AnyEvent::HTTPD::HTTPServer;
use strict;
no warnings;

use IO::Socket::INET;
use Object::Event;
use AnyEvent::Handle;
use AnyEvent::Util;

use AnyEvent::HTTPD::HTTPConnection;

our @ISA = qw/Object::Event/;

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

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   my $sock =
      $self->{sock} =
         IO::Socket::INET->new (
            Listen => 10,
            LocalPort => $self->{port},
            ReuseAddr => 1,
            Blocking => 0
         );

   $sock or die "Couldn't create listening socket: $!";

   $self->{lw} = AnyEvent::Util::listen ($sock, sub {
      my ($sock) = @_;

      my $htc = AnyEvent::HTTPD::HTTPConnection->new (fh => $sock);
      $self->{handles}->{$htc} = $htc;

      $htc->reg_cb (disconnect => sub {
         delete $self->{handles}->{$_[0]};
         $self->event (disconnect => $_[0])
      });

      $self->event (connect => $htc);

   }, sub {
      $self->event (error => $!);
   });

   return $self
}

1;
