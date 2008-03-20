package BS::HTTPD::HTTPConnection;
use feature ':5.10';
use HTTP::Date;
use strict;
no warnings;

use BS::HTTPD::TCPConnection;

our @ISA = qw/BS::HTTPD::TCPConnection/;

sub new {
   my $this  = shift;
   my $class = ref($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->reg_cb (
      data => sub { my ($self) = @_; $self->handle_data ($_[1]); },
      disconnect => sub {
         my ($self) = @_;
         # TODO: this is not tested yet:
         if ($self->{last_header}) {
            $self->handle_request (@{delete $self->{last_header}}, $self->read_buffer);
         }
      }
   );

   #$self->reg_cb (
   #   request => sub {
   #      my ($self, $m, $u, $hdr, $cont) = @_;
   #      warn "REQUEST $m / $u: ".join (',', %$hdr)." [$cont]\n";
   #      if ($u =~ /test/) {
   #         $self->response (
   #            200, "ok", {'Content-type' => 'text/html'},
   #            "<form method=POST>"
   #            ."<input type='file' name='bla' /><input type='text' name='test' />"
   #            ."<input type='submit' /></form>"
   #         );

   #      } else {
   #         $self->response (
   #            200, "ok", {'Content-type' => 'text/html'},
   #            "<form enctype='multipart/form-data' method=POST>"
   #            ."<input type='file' name='bla' /><input type='text' name='test' />"
   #            ."<input type='submit' /></form>"
   #         );
   #      }
   #   }
   #);

   return $self
}


sub error {
   my ($self, $code, $msg, $hdr, $content) = @_;

   if ($code !~ /^(1\d\d|204|304)$/) {
      $content //= "$code $msg";
      $hdr->{'Content-Type'} = 'text/plain';
   }

   $self->response ($code, $msg, $hdr, $content);
}

sub response {
   my ($self, $code, $msg, $hdr, $content) = @_;
   my $res = "HTTP/1.1 $code $msg\015\012";
   $hdr->{'Expires'} = $hdr->{'Date'} = time2str time;
   $hdr->{'Cache-Control'} = "max-age=0";

   if ($hdr->{'Transfer-Encoding'} eq 'chunked') {
      $self->{chunked} = 1;
   }

   if ($self->{chunked}) {
      $hdr->{'Transfer-Encoding'} = 'chunked';
   } else {
      $hdr->{'Content-Length'} = length $content;
   }

   while (my ($h, $v) = each %$hdr) {
      $res .= "$h: $v\015\012";
   }
   $res .= "\015\012";

   if (!$self->{chunked}) {
      $res .= $content;
   }
   $self->write_data ($res);

   if ($self->{chunked}) {
      $self->chunk ($content);
   }
}

sub chunk {
   my ($self, $chunk, $exts, $is_last) = @_;

   my $len = sprintf "%x", length $chunk;
   my $chunkdat = $len;
   if (defined $exts) {
      for (keys %$exts) {
         $chunkdat .= ";" . $_ . (defined $exts->{$_} ? "=$exts->{$_}" : "");
      }
   }
   my $chunked_body = $chunkdat . "\015\012" . $chunk . "\015\012";
   $self->write_data ($chunked_body);

   if ($is_last) {
      $self->write_data ("0\015\012\015\012");
      $self->{chunked} = 0;
   }
}

sub _unquote {
   my ($str) = @_;
   if ($str =~ /^"(.*?)"$/) {
      $str = $1;
      my $obo = '';
      while ($str =~ s/^(?:([^"]+)|\\(.))//s) {
        $obo .= $1;
      }
      $str = $obo;
   }
   $str
}

sub _parse_headers {
   my ($header) = @_;
   my $hdr;

   while ($header =~ /\G
      (?<header>[^:\000-\040]+) : [\011\040]* 
         (?<cont> (?:[^\015\012]+|\015\012[\011\040])* )
         \015\012
      /sgx) {

      $hdr->{$+{header}} .= ",$+{cont}"
   }
   for (keys %$hdr) { $hdr->{$_} = substr $hdr->{$_}, 1; }
   $hdr
}

sub decode_part {
   my ($self, $hdr, $cont) = @_;

   $hdr = _parse_headers ($hdr);
   if ($hdr->{'Content-Disposition'} =~ /form-data/) {
      my ($dat, $name_para) = split /\s*;\s*/, $hdr->{'Content-Disposition'};
      my ($name, $par) = split /\s*=\s*/, $name_para;
      if ($par =~ /^".*"$/) { $par = _unquote ($par) }
      return ($par, $cont, $hdr->{'Content-Type'});
   }
   ();
}

sub decode_multipart {
   my ($self, $cont, $boundary) = @_;

   my $parts = {};

   while ($cont =~ s/
      ^--\Q$boundary\E              \015\012
      (?<header> (?:.*?\015\012)* ) \015\012
      (?<cont>.*?) \015\012
      (--\Q$boundary\E (?<end>--)?  \015\012)
      /\3/xs) {
      my ($h, $c, $e) = ($+{header}, $+{cont}, $+{end});

      if (my (@p) = $self->decode_part ($h, $c)) {
         push @{$parts->{$p[0]}}, [$p[1], $p[2]];
      }

      last if $e eq '--';
   }
   return $parts;
}

# application/x-www-form-urlencoded  
#
# This is the default content type. Forms submitted with this content type must
# be encoded as follows:
#
#    1. Control names and values are escaped. Space characters are replaced by
#    `+', and then reserved characters are escaped as described in [RFC1738],
#    section 2.2: Non-alphanumeric characters are replaced by `%HH', a percent
#    sign and two hexadecimal digits representing the ASCII code of the
#    character. Line breaks are represented as "CR LF" pairs (i.e., `%0D%0A').
#
#    2. The control names/values are listed in the order they appear in the
#    document. The name is separated from the value by `=' and name/value pairs
#    are separated from each other by `&'.
#

sub _url_unescape {
   my ($val) = @_;
   $val =~ s/\+/ /g;
   $val =~ s/%([0-9a-f][0-9a-f])/chr (hex ($1))/eg;
   $val
}

sub parse_urlencoded {
   my ($self, $cont) = @_;
   my (@pars) = split /\&/, $cont;
   $cont = {};

   for (@pars) {
      my ($name, $val) = split /=/, $_;
      $name = _url_unescape ($name);
      $val  = _url_unescape ($val);

      push @{$cont->{$name}}, [$val, ''];
   }
   $cont
}

sub handle_request {
   my ($self, $method, $uri, $hdr, $cont) = @_;

   my ($c, @params) = split /\s*;\s*/, $hdr->{'Content-Type'};
   my $bound;
   for (@params) {
      if (/^\s*boundary\s*=\s*(.*?)\s*$/) {
         $bound = _unquote ($1);
      }
   }

   #d#require Data::Dumper;

   if ($c eq 'multipart/form-data') {
      $cont = $self->decode_multipart ($cont, $bound);
      #d#warn "DUMP[". Data::Dumper::Dumper ([$cont]). "]\n";

   } elsif ($c =~ /x-www-form-urlencoded/) {
      $cont = $self->parse_urlencoded ($cont);
      #d# warn "DUMP[". Data::Dumper::Dumper ([$cont]). "]\n";
   }

   $self->event (request => $method, $uri, $hdr, $cont);
}

sub handle_data {
   my ($self, $rbuf) = @_;
   #d# warn "BUF[$$rbuf]\n";

   if ($self->{content_len}) {
      if ($self->{content_len} <= length $$rbuf) {
         my $cont = substr $$rbuf, 0, $self->{content_len};
         $$rbuf = substr $$rbuf, $self->{content_len};
         $self->handle_request (@{delete $self->{last_header}}, $cont);
         delete $self->{content_len};
      }
   } else {
      if ($$rbuf =~ s/^
             (?<method>\S+) \040 (?<uri>\S+) \040 HTTP\/(?<ver> \d+\.\d+ ) \015\012
             (?<headers> (?:[^\015]+\015\012)* ) \015\012//sx) {

         my ($m, $u, $h) = ($+{method},$+{uri},$+{headers});
         my $hdr = {};

         if ($m ne 'GET' && $m ne 'HEAD' && $m ne 'POST') {
            $self->error (405, "method not allowed", { Allow => "GET,HEAD" });
            return;
         }

         if ($+{ver} >= 2) {
            $self->error (506, "http protocol version not supported");
            return;
         }

         $hdr = _parse_headers ($h);

         $self->{last_header} = [$+{method}, $+{uri}, $hdr];

         if (defined $hdr->{'Content-Length'}) {
            $self->{content_len} = $hdr->{'Content-Length'};
            $self->handle_data ($rbuf);
         } else {
            $self->handle_request (@{$self->{last_header}});
         }
      }
   }
}

1;
