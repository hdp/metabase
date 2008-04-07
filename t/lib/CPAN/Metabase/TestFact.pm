package CPAN::Metabase::TestFact;
use base 'CPAN::Metabase::Fact';

use MIME::Base64 ();
use Data::Dumper ();
use Carp ();

sub odor { if (@_ > 1) { $_[0]->{odor} = $_[1] }; return $_[0]->{odor} }

sub new { 
    my ($class, $args) = @_;
    Carp::croak "$class\->new() takes a hashref" unless ref $args eq 'HASH';    
    return bless { %$args, type => 'smell'}, $class;
}

sub as_string {
  my ($self) = @_;

  my $hash = { odor => $self->odor };
  return MIME::Base64::encode_base64(Data::Dumper::Dumper($hash));
}

sub from_string { 
  my ($class, $string) = @_;

  $string = $$string if ref $string;

  my $perl = MIME::Base64::decode_base64($string);

  $class->new(eval $perl);
}

1;