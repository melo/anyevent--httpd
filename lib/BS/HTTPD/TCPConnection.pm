package BS::HTTPD::TCPConnection;
use feature ':5.10';
use strict;
no warnings;

#use Compress::Zlib; # No need for compression yet

use Fcntl;
use POSIX;
use IO::Socket::INET;
use Socket qw/IPPROTO_TCP TCP_NODELAY/;
use BS::Event;
our @ISA = qw/BS::Event/;

=head1 NAME

BS::HTTPD::TCPConnection - This class handles basic TCP input/output

=head1 DESCRIPTION

This class is a helper class for L<BS:HTTPD::HTTPConnection>.

It has no public interface yet.

=head1 COPYRIGHT & LICENSE

Copyright 2008 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = { @_ };
   bless $self, $class;
   if (exists $self->{socket}) {
      binmode $self->{socket};
      _set_noblock ($self->{socket});
   }
   $self->init;
   return $self;
}

sub init { }

sub _set_noblock {
   my ($s) = @_;
   my $flags = 0;
   fcntl($s, F_GETFL, $flags)
       or die "Couldn't get flags for HANDLE : $!\n";
   $flags |= O_NONBLOCK;
   fcntl($s, F_SETFL, $flags)
       or die "Couldn't set flags for HANDLE: $!\n";
}

sub is_connected {
   my ($self) = @_;
   not not $self->{socket}
}

sub connect {
   my ($self, $host, $port) = @_;

   unless (defined $host) { $host = $self->{host}; }
   unless (defined $port) { $port = $self->{port}; }

   $self->{socket}
      and return;

   my $sock = IO::Socket::INET->new (
      PeerAddr => $host,
      PeerPort => $port,
      Proto    => 'tcp',
      Blocking => 0,
   ) or die "Couldn't connect to $host:$port: $!";

   $self->{socket} = $sock;
   $self->{host}   = $host;
   $self->{port}   = $port;

   binmode $sock;
   setsockopt ($sock, IPPROTO_TCP, TCP_NODELAY, 1);

   delete $self->{write_buffer};
   delete $self->{read_buffer};

   $self->{cw} =
      AnyEvent->io (poll => 'w', fh => $sock, cb => sub {
         if ($! = $sock->sockopt (SO_ERROR)) {
            $self->event (connect_error => $!);
            $self->cleanup;
         } else {
            _set_noblock ($self->{socket});
            $self->start_reader;
            $self->start_writer;
            $self->event ('connect');
         }
         delete $self->{cw};
      });
}

sub cleanup {
   my ($self) = @_;
   delete $self->{cw};
   delete $self->{r};
   delete $self->{w};
   delete $self->{write_buffer};
   delete $self->{read_buffer};
   delete $self->{compress};
   delete $self->{uncompress};
   eval {
      $self->{socket}->close;
   };
   delete $self->{socket};
}

sub disconnect {
   my ($self, $reason) = @_;
   $self->event (disconnect => $reason || "Disconnect without reason.");
   $self->cleanup;
}

sub read_buffer { $_[0]->{read_buffer} }

sub start_reader {
   my ($self) = @_;

   my ($host, $port, $sock) = ($self->{host}, $self->{port}, $self->{socket});

   $self->{r} =
      AnyEvent->io (poll => 'r', fh => $sock, cb => sub {
         my $l = sysread $sock, my $data, 4096;

         if (defined $l) {
            if ($l == 0) {
               $self->disconnect ("EOF from bummskraut_server '$host:$port'");
            } else {
               $self->{read_buffer} .= $data;
               $self->{compress_stat}->{in_comp} += length $data if $self->{uncompress};
               $self->handle_data (\$self->{read_buffer});
            }

         } else {
            return if $! == EAGAIN();
            $self->disconnect (
               "Error while reading from bummskraut server '$host:$port': $!"
            );
         }
      });
}

sub start_writer {
   my ($self) = @_;
   return unless $self->{r};
   return unless length ($self->{write_buffer}) > 0;

   unless ($self->{w}) {
      $self->{w} =
         AnyEvent->io (poll => 'w', fh => $self->{socket}, cb => sub {
            my $data = $self->{write_buffer};

            if (defined ($data) && $data ne '') {
               my $len = syswrite $self->{socket}, $data;

               if (defined $len) {
                  if ($len == length $self->{write_buffer}) {
                     if ($self->{buffer_empty_close}) {
                        $self->disconnect ("simple request finished");
                     }
                     delete $self->{w};
                  }

                  $self->{write_buffer} = substr $self->{write_buffer}, $len;
               } else {
                  return if $! == EAGAIN();
                  $self->disconnect (
                     "Error when writing data on $self->{host}:$self->{port}: $!"
                  );
               }
            }
         });
   }
}

sub handle_data {
   my ($self, $buf) = @_;

  # if ($self->{uncompress}) {
  #    my ($out, $status) = $self->{uncompress}->inflate ($$buf);
  #    defined $out or die "Couldn't uncompress, error!";
  #    $self->{uncompress_buffer} .= $out;
  #    $self->{compress_stat}->{in_uncomp} += length $out if $self->{uncompress};
  #    $buf = \$self->{uncompress_buffer};
  # }

   $self->event (data => $buf);
}

# TODO: no need for compression yet
#sub enable_compression {
#   my ($self) = @_;
#
#   my ($d, $status) = deflateInit ();
#   $self->{compress} = $d;
#   my ($i, $status_i) = inflateInit ();
#   $self->{uncompress} = $i;
#
#   $self->{read_buffer}  = '';
#   $self->{write_buffer} = '';
#
#   $self->start_compres_statistics_timer;
#}

sub start_compres_statistics_timer {
   my ($self) = @_;
   $self->{compres_stat_timer} = AnyEvent->timer (after => 10, cb => sub {
      my $s = $self->{compress_stat};
      if ($s->{in_uncomp} != $self->{last_in_uncomp} || $s->{out_uncomp} != $self->{last_out_uncomp}) {
         warn
            (sprintf "IN: %d/%d %.2f%% OUT: %d/%d %.2f%% POUT: (%d pkts) %.1f bpp PIN: (%d pkts) %.1f bpp\n",
                $s->{in_uncomp}, $s->{in_comp}, (100 / $s->{in_uncomp}) * ($s->{in_uncomp} - $s->{in_comp}),
                $s->{out_uncomp}, $s->{out_comp}, (100 / $s->{out_uncomp}) * ($s->{out_uncomp} - $s->{out_comp}),
                $s->{out_packets}, ($s->{out_uncomp} - $s->{out_comp}) / $s->{out_packets},
                $s->{in_packets}, ($s->{in_uncomp} - $s->{in_comp}) / $s->{in_packets});

         $self->{last_in_uncomp} = $s->{in_uncomp};
         $self->{last_out_uncomp} = $s->{out_uncomp};
      }
      $self->start_compres_statistics_timer;
   });
}

sub write_data {
   my ($self, $data) = @_;

  # if ($self->{compress}) {
  #    my $pkt_len = length $data;
  #    $self->{compress_stat}->{out_uncomp} += $pkt_len;
  #    my $out = $self->{compress}->deflate ($data);
  #    defined $out or die "Couldn't deflate, error!";
  #    my $inl = length $data;
  #    $data = $out;
  #    my $fout = $self->{compress}->flush (Z_SYNC_FLUSH);
  #    defined $fout or die "Couldn't flush deflate, error!";
  #    $data .= $fout;
  #    $self->{compress_stat}->{out_comp} += length $data;
  #    $self->{compress_stat}->{out_packets}++;
  #    open OUTCOMPR, ">/tmp/infl.tmp";
  #    print OUTCOMPR $data;
  #    close OUTCOMPR;
  # }

   $self->{write_buffer} .= $data;
   $self->start_writer;
}

sub set_close_on_write_completion {
   my ($self) = @_;
   $self->{buffer_empty_close} = 1;
}

1;

1;
