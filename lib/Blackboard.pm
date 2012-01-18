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
present, some of which may require lookups from other services.  Maintaining
these data-dependencices in a decentralized fashion can eventually lead to
disparity in the control of a workflow, and possibly missed opportunities for
optimizing parallelism.  This module attempts to address this design issue by
allowing the data dependencies and subsequent workflow to be descriptively
defined in a central place.

=cut

use strict;
use warnings FATAL => "all";
use Mouse;
use AnyEvent;

=head1 ATTRIBUTES

=over 4

=item objects

The objects present in this blackboard instance.

=cut

has objects   => (
    is      => "ro",
    isa     => "HashRef[Any]",
    default => sub { {} }
);

=item watchers

A hash reference of callbacks for each watcher, with the key for the watcher as
its key.

=cut

has watchers  => (
    is      => "ro",
    isa     => "HashRef[ArrayRef[CodeRef]]",
    default => sub { {} }
);

=item interests

A hash table with which has each watcher as a key, and array reference to an
array of interested keys as a value.

=cut

has interests => (
    is      => "ro",
    isa     => "HashRef[ArrayRef[Str]]",
    default => sub { {} }
);

=back

=cut

no Mouse;

=head1 METHODS

=over 4

=item has KEY

Returns true if the blackboard has a value for the given key, false otherwise.

=cut

sub has {
    my ($self, $key) = @_;

    return exists $self->objects->{$key};
}


=item watch KEYS, WATCHER

=item watch KEY, WATCHER

Given an array ref of keys (or a single key as a string) and an array ref
describing a watcher, register the watcher for a dispatch when the given data
elements are provided.  The watcher may be either an array reference to a tuple
of [ $object, $method_name ] or a subroutine reference.

In the instance that a value has already been provided for this key, the
dispatch will happen immediately.

=cut

# Create a callback subref from a tuple.
sub _callback {
    my ($self, $object, $method) = @_;

    return sub {
        $object->$method(@_);
    };
}

# Dispatch this watcher if it's interests are all available.
sub _dispatch {
    my ($self, $watcher) = @_;

    my $interests = $self->interests->{$watcher};

    # Determine if all interests for this watcher have defined keys (some
    # kind of value, including undef).
    if (@$interests == grep $self->has($_), @$interests) {
        $watcher->(@{ $self->objects }{@$interests});
    }
}

sub watch {
    my ($self, $keys, $watcher) = @_;

    if (ref $watcher eq "ARRAY") {
        $watcher = $self->_callback(@$watcher);
    }

    unless (ref $keys) {
        $keys = [ $keys ];
    }

    for my $key (@$keys) {
        push @{ $self->watchers->{$key} ||= [] }, $watcher;
    }

    $self->interests->{$watcher} = $keys;

    $self->_dispatch($watcher);
}

=item found KEY

Notify any watchers of a key that it has been found, if all of their other
interests have been found.  This method is usually not invoked by the client.

=cut

sub found {
    my ($self, $key) = @_;

    for my $watcher (@{$self->watchers->{$key}}) {
        $self->_dispatch($watcher);
    }
}

=item put KEY, VALUE [, KEY, VALUE .. ]

Put the given keys in the blackboard and notify all watchers of those keys that
the objects have been found, if and only if the value has not already been
placed in the blackboard.

=cut

sub put {
    my ($self, %found) = @_;

    for my $key (grep not($self->has($_)), keys %found) {
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

Clear the blackboard of all values.

=cut

sub clear {
    my ($self) = @_;

    $self->objects({});
}

=item timeout KEY, SECONDS [, DEFAULT ]

Set a timer for N seconds to provide "default" value as a value, defaults to
`undef`.  This can be used to ensure that blackboard workflows do not reach a
dead-end if a required value is difficult to obtain.

=cut
sub timeout {
    my ($self, $key, $seconds, $default) = @_;

    my $guard = AnyEvent->timer(
        after => $seconds,
        cb    => sub {
            $self->put($key => $default) unless $self->has($key);
        }
    );

    # Cancel the timer if we find the object first (otherwise this is a NOOP).
    $self->watch($key => sub { undef $guard });
}

=item hangup

Clear all watchers.

=cut

sub hangup {
    my ($self) = @_;

    $self->watchers({});
}

=item clone

Create a clone of this blackboard.  This will not dispatch any events, even if
the blackboard is prepopulated.

=cut

sub clone {
    my ($self) = @_;

    my $objects   = { %{ $self->objects } };
    my $watchers  = { %{ $self->watchers } };
    my $interests = { %{ $self->interests } };

    for my $watcher (keys %$interests) {
        $interests->{$watcher} = [ @{ $interests->{$watcher} } ];
    }

    return __PACKAGE__->new(
        objects   => $objects,
        watchers  => $watchers,
        interests => $interests,
    );
}

=back

=cut

return __PACKAGE__;

=head1 BUGS

Unlikely.  This module is exceedingly simple.

=head1 LICENSE

Copyright (C) 2011, Say Media.  Distribution Prohibited.

=cut
