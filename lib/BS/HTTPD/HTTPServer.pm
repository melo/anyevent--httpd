package BS::HTTPD::HTTPServer;
use feature ':5.10';
use strict;
no warnings;

use BS::HTTPD::TCPListener;
use BS::HTTPD::HTTPConnection;

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
