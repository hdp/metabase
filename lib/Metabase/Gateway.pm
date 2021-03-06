package Metabase::Gateway;
use Moose;

use Metabase::Librarian;
use Data::GUID;

use Metabase::Fact;
use Metabase::User::Profile;

# XXX life becomes a lot easier if we say that fact classes MUST have 1-to-1 
# relationship with a .pm file. -- dagolden, 2009-03-31

has fact_classes => (
  is  => 'ro',
  isa => 'ArrayRef[Str]',
  auto_deref => 1,
  required   => 1,
);

has approved_types => (
  is          =>  'ro',
  isa         =>  'ArrayRef[Str]',
  auto_deref  => 1,
  lazy        => 1,
  builder     => '_build_approved_types',
);

has autocreate_profile => (
  is          => 'ro',
  isa         => 'Bool',
  default     => 0,
);

has librarian => (
  is       => 'ro',
  isa      => 'Metabase::Librarian',
  required => 1,
);

has secret_librarian => (
  is       => 'ro',
  isa      => 'Metabase::Librarian',
  required => 1,
);

# recurse report classes -- less to specify to new()
sub _build_approved_types {
  my ($self) = @_;
  my @queue = $self->fact_classes;
  my @approved;
  while ( my $class = shift @queue ) {
    push @approved, $class;
    # XXX $class->can('fact_classes') ?? -- dagolden, 2009-03-31
    push @queue, $class->fact_classes if $class->isa('Metabase::Report');
  }
  return [ map { $_->type } @approved ];
}

sub _validate_resource {
  my ($self, $request) = @_;

  # XXX Well... yeah, eventually we'll want to reject reports for dists that
  # don't, you know, exist. -- rjbs, 2008-04-06
  1;
}

sub __submitter_profile {
  my ($self, $profile_struct) = @_;
  # I hate nearly every variable name in this scope. -- rjbs, 2009-03-31

  my $profile_guid = $profile_struct->{metadata}{core}{guid}[1];
  my $given_fact = eval {
    Metabase::User::Profile->from_struct($profile_struct);
  };

  die "invalid submitter profile" unless $given_fact; # bad profile provided

  my $profile_fact = eval {
    $self->secret_librarian->extract($profile_guid);
  };

  # if not found, maybe autocreate it
  if ( ! $profile_fact ) {
    die "unknown submitter profile" unless $self->autocreate_profile;
    $self->secret_librarian->store( $given_fact ); # XXX check fail -- dagolden, 2009-04-05
    return $given_fact;
  }

  my ($profile_secret_fact) = grep { $_->isa('Metabase::User::Secret') }
                              $profile_fact->facts;

  my ($given_secret_fact)   = grep { $_->isa('Metabase::User::Secret') }
                              $given_fact->facts;

  my $profile_secret = $profile_secret_fact->content;
  my $given_secret   = $given_secret_fact->content;

  die "submitter could not be authenticated"
    unless defined $profile_secret
    and    defined $given_secret
    and    $profile_secret eq $given_secret;

  return $profile_fact;
}

sub _validate_fact_struct {
  my ($self, $struct) = @_;

  die "no content provided" unless defined $struct->{content};

  for my $key ( qw/resource type schema_version guid creator_id/ ) {
    my $meta = $struct->{metadata}{core}{$key};
    die "no '$key' provided in core metadata"
      unless defined $meta;
    die "invalid '$key' provided in core metadata"
      unless ref $meta eq 'ARRAY';
    # XXX really should check meta validity: [ Str => 'abc' ], but lets wait
    # until we decide on sugar for metadata types -- dagolden, 2009-03-31
  }

  die "submissions must not include resource or content metadata"
    if $struct->{metadata}{content} or $struct->{metadata}{resource};
}

sub _check_permissions {
  my ($self, $profile, $action, $fact) = @_;

  # The devil may care, but we don't. -- rjbs, 2009-03-30
  return 1;
}

sub handle_submission {
  my ($self, $struct) = @_;

  my $fact_struct    = $struct->{fact};
  my $profile_struct = $struct->{submitter};

  # use Data::Dumper;
  # local $SIG{__WARN__} = sub { warn "@_: " . Dumper($struct); };

  my $profile = eval { $self->__submitter_profile($profile_struct) };
  die "reason: $@" unless $profile;

  $self->_validate_fact_struct($fact_struct);

  my $type = $fact_struct->{metadata}{core}{type}[1];

  die "'$type' is not an approved fact type"
    unless grep { $type eq $_ } $self->approved_types;

  my $class = Metabase::Fact->class_from_type($type);

  my $fact = eval { $class->from_struct($fact_struct) }
    or die "Unable to create a '$class' object: $@";

  $self->_check_permissions($profile => submit => $fact);

  return $self->enqueue($fact, $profile);
}

sub enqueue {
  my ($self, $fact, $profile) = @_;
  return $self->librarian->store($fact, $profile);
}

1;
