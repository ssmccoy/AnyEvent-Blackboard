package Blackboard;

=head1 NAME

Blackboard - A simple blackboard database and dispatcher.

=head1 SYNOPSIS

  my $blackboard = Blackboard->new();

  $blackboard->watch([qw( foo bar )], [ $object, "found_foobar" ]);
  $blackboard->watch(foo => [ $object, "found_foo" ]);

  $blackboard->put(foo => "First dispatch");
  # $object->found_foo("First dispatch") is called
  $blackboard->put(bar => "Second dispatch");
  # $object->found_foobar("Second dispatch") is called

  $blackboard->clear;

  $blackboard->put(bar => "Future Dispatch");
  # No dispatch is called...
  # but $blackboard->get("bar") eq "Future Dispatch"

  $blackboard->put(foo => "Another dispatch");

  # Order of the following is undefined:
  #
  # $object->found_foo("Future dispatch") is called
  # $object->found_foobar("Another dispatch") is called

  $blackboard->hangup;

=head1 RATIONALE

Concurrent applications can often do one or more thing at a time while
"waiting" for a response from a given service.  Conversely, sometimes
applications cannot dispatch all requests until certain data elements are
present, and those may require lookups from other services.  Maintaining these
data-dependencices in a decentralized fashion can eventually lead to a
fragmented codebase.  This module attempts to address this design issue by
allowing the data dependencies and subsequent workflow to be descriptively
defined in a central place.

=cut

use Moose;

=head1 ATTRIBUTES

=over 4

=item objects

The objects present in this blackboard instance.

=cut

has objects   => (
    is      => "ro",
    isa     => "HashRef[Object]",
    default => sub { {} }
);

=item watchers

The a lists of watchers

=cut

has watchers  => (
    is      => "ro",
    isa     => "HashRef[ArrayRef]",
    default => sub { {} }
);

=item interests

A table of interests of a given watcher.

=cut

has interests => (
    is      => "ro",
    isa     => "HashRef[ArrayRef[Str]]",
    default => sub { {} }
);

=back

=cut


=head1 METHODS

=over 4

=item watch KEYS, WATCHER

=item watch KEY, WATCHER

Given an array ref of keys (or a single key as a string) and an array ref
describing a watcher, register the watcher for a dispatch when the given data
elements are provided.

=cut
sub watch {
    my ($self, $keys, $watcher) = @_;

    unless (ref $keys) {
        $keys = [ $keys ];
    }

    for my $key (@$keys) {
        push @{ $self->watchers->{$key} ||= [] }, $watcher;
    }

    $self->interests->{$watcher} = $keys;
}

=item found KEY

Notify any watchers of a key that it has been found, if all of their other
interests have been found.

=cut

sub found {
    my ($self, $key) = @_;

    for my $watcher (@{$self->watchers->{$key}}) {
        my $interests = $self->interests->{$watcher};

        if (defined @{$self->objects}{@$interests}) {
            my ($object, $message) = @$watcher;

            $object->$message( @{ $self->objects->{@$interests} } );
        }
    }
}

=item put KEY, VALUE [, KEY, VALUE .. ]

Put the given keys in the blackboard and notify all watchers of those keys that
the objects have been found.

=cut

sub put {
    my ($self, %found) = @_;

    for my $key (keys %found) {
        $self->objects->{$key} = $found{$key};

        $self->found($key);
    }
}

=item get KEY

Fetch the value of a key.

=cut

sub get {
    my ($self, $key) = @_;

    return $self->objects->{$key};
}

=item clear

Clear the blackboard of all keys.

=cut

sub clear {
    my ($self) = @_;

    $self->objects({});
}

=item hangup

Clear all watchers.

=cut

sub hangup {
    my ($self) = @_;

    $self->watchers({});
    $self->interests({});
}

=back

=cut

return __PACKAGE__;

=head1 BUGS

Unlikely.  This module is exceedingly simple.

=head1 LICENSE

Copyright (C) 2011, Say Media.  Distribution Prohibited.

=cut
