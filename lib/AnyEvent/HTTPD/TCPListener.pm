package AnyEvent::HTTPD::TCPListener;
use strict;
use Socket;
use AnyEvent;
use IO::Socket::INET;
use Object::Event;
use AnyEvent::HTTPD::TCPConnection;

our @ISA = qw/Object::Event/;

=head1 NAME

AnyEvent::HTTPD::TCPListener - A TCP listener

=head1 DESCRIPTION

This class handles new TCP connections for L<AnyEvent::HTTPD::HTTPServer>.

It has no public interface yet.

=head1 COPYRIGHT & LICENSE

Copyright 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut



sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = {@_};
   bless $self, $class;
   $self->start_listener;
   return $self;
}

sub start_listener {
   my ($self) = @_;

   my $sock = IO::Socket::INET->new(
         Listen    => 5,
         ReuseAddr => 1,
         Reuse     => 1,
         LocalPort => $self->{port} || 8012,
         Proto     => 'tcp'
   );

   $sock or die "Couldn't create listener: $!";

   $self->{listener} =
      AnyEvent->io (poll => 'r', fh => $sock, cb => sub {
         my $cl = $sock->accept ()
            or die "couldn't accept client: $!";
         $cl->autoflush (1);
         $self->handle_client ($cl);
      });
}

sub foreach_client {
   my ($self, $cb, @arg) = @_;
   for (values %{$self->{clients}}) {
      $cb->($self, $_, @arg);
   }
}

sub foreach_client_except {
   my ($self, $ex, $cb, @arg) = @_;
   for (grep { $ex ne $_ } values %{$self->{clients}}) {
      $cb->($self, $_, @arg);
   }
}

sub connection_class {
   'AnyEvent::HTTPD::TCPConnection'
}

sub spawn_connection {
   my ($self, $cl, $chost, $cport, @args) = @_;

   my $class = $self->connection_class;

   my $con = $class->new (
      socket => $cl,
      host => $chost,
      port => $cport,
      @args
   );
   $con->reg_cb (disconnect => sub {
      my ($cl) = @_;
      $self->event (disconnect => $cl);
      delete $self->{clients}->{$cl};
   });
   $con
}

sub handle_client {
   my ($self, $cl) = @_;
   my ($chost, $cport) = ($cl->peerhost (), $cl->peerport ());
   my $lid = "$chost:$cport";

   $cl = $self->spawn_connection ($cl, $chost, $cport);
   $self->{clients}->{"$cl"} = $cl;
   $self->event (connect => $cl);
   $cl->start_reader;
   $cl->start_writer;
}

1;
