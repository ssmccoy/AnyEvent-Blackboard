package AnyEvent::Blackboard;

=head1 NAME

AnyEvent::Blackboard - A simple blackboard database and dispatcher.

=head1 SYNOPSIS

  my $blackboard = AnyEvent::Blackboard->new();

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

our $VERSION = 0.2.5;

=for ATTRIBUTES

=over 4

=for _objects

The _objects present in this blackboard instance.

=cut

has _objects   => (
    is      => "rw",
    isa     => "HashRef[Any]",
    default => sub { {} }
);

=for _watchers

A hash reference of callbacks for each watcher, with the key for the watcher as
its key.

=cut

has _watchers  => (
    is      => "rw",
    isa     => "HashRef[ArrayRef[CodeRef]]",
    default => sub { {} }
);

=for _interests

A hash table with which has each watcher as a key, and array reference to an
array of interested keys as a value.

=cut

has _interests => (
    is      => "rw",
    isa     => "HashRef[ArrayRef[Str]]",
    default => sub { {} }
);

=back

=cut

no Mouse;

=head1 CONSTRUCTORS

AnyEvent::Blackboard includes a static builder method for constructing
prototype blackboards using concise syntax.  The is should typically be used
whenever describing a workflow in detail prior to use (and then cloning the
blackboard) is the desired usecase.

=over 4

=item build watchers => [ ... ]

=item build values => [ ... ]

=item build watchers => [ ... ], values => [ ... ]

Build and return a blackboard prototype, it takes a balanced list of keys and
array references, with the keys specifying the method to call and the array
reference specifying the argument list.  This is a convenience method which is
short hand explained by the following example:

    my $blackboard = AnyEvent::Blackboard->new();

    $blackboard->watch(@$watchers);
    $blackboard->put(@$values);

    # This is equivalent to
    my $blackboard = AnyEvent::Blackboard->build(
        watchers => $watchers,
        values   => $values
    );

=cut

# This is now a legacy thing, on a one month old component...good job.
sub build {
    confess "Build requires a balanced list of arguments" unless @_ % 2;

    my ($class, %args) = @_;

    my ($watchers, $values) = @args{qw( watchers values )};

    my $blackboard = $class->new();

    $blackboard->watch(@$watchers) if $watchers;
    $blackboard->put(@$values)     if $values;

    return $blackboard;
}

=head1 METHODS

=over 4

=item has KEY

Returns true if the blackboard has a value for the given key, false otherwise.

=cut

sub has {
    my ($self, $key) = @_;

    return exists $self->_objects->{$key};
}


=item watch KEYS, WATCHER

=item watch KEY, WATCHER

Given an array ref of keys (or a single key as a string) and an array ref
describing a watcher, register the watcher for a dispatch when the given data
elements are provided.  The watcher may be either an array reference to a tuple
of [ $object, $method_name ] or a subroutine reference.

In the instance that a value has already been provided for this key, the
dispatch will happen immediately.

Returns a reference to self so the builder pattern can be used.

=cut

# Create a callback subref from a tuple.
sub _callback {
    my ($self, $object, $method) = @_;

    return sub {
        $object->$method(@_);
    };

    return $self;
}

# Dispatch this watcher if it's _interests are all available.
sub _dispatch {
    my ($self, $watcher) = @_;

    my $interests = $self->_interests->{$watcher};

    # Determine if all _interests for this watcher have defined keys (some
    # kind of value, including undef).
    if (@$interests == grep $self->has($_), @$interests) {
        $watcher->(@{ $self->_objects }{@$interests});
    }
}

sub watch {
    my ($self, @args) = @_;

    while (@args) {
        my ($keys, $watcher) = splice @args, 0, 2;

        if (ref $watcher eq "ARRAY") {
            $watcher = $self->_callback(@$watcher);
        }

        unless (ref $keys) {
            $keys = [ $keys ];
        }

        for my $key (@$keys) {
            push @{ $self->_watchers->{$key} ||= [] }, $watcher;
        }

        $self->_interests->{$watcher} = $keys;

        $self->_dispatch($watcher);
    }
}

=item watcher KEY

=item watcher KEYS

Given a key or an array reference of keys, return all watchers interested in
the given key.

=cut

sub watchers {
    my ($self, $keys) = @_;

    $keys = [ $keys ] unless ref $keys;

    my @results;

    push @results, @{ $self->_watchers->{$_} } for @$keys;

    return @results;
}

=item found KEY

Notify any watchers of a key that it has been found, if all of their other
_interests have been found.  This method is usually not invoked by the client.

=cut

sub found {
    my ($self, $key) = @_;

    for my $watcher (@{$self->_watchers->{$key}}) {
        $self->_dispatch($watcher);
    }
}

=item put KEY, VALUE [, KEY, VALUE .. ]

Put the given keys in the blackboard and notify all watchers of those keys that
the objects have been found, if and only if the value has not already been
placed in the blackboard.

The `found` method is invoked for each key, as the key is added to the
blackboard.

=cut

sub put {
    my ($self, %found) = @_;

    my @keys;

    for my $key (grep not($self->has($_)), keys %found) {
        $self->_objects->{$key} = $found{$key};

        $self->found($key);
    }
}

=item delete KEY [, KEY ...]

Given a list of keys, remove them from the blackboard.  This method should be
used with I<caution>, since watchers are not notified that the values are
removed but they will be re-notified when a new value is provided.

=cut

sub remove {
    my ($self, @keys) = @_;

    delete @{$self->_objects}{@keys};
}

=item replace KEY, VALUE [, KEY, VALUE .. ]

Given a list of key value pairs, replace those values on the blackboard.
Replacements have special semantics, unlike calling `remove` and `put` on a
single key in succession, calling `replace` will not notify any watchers of the
given keys on this blackboard.  But watchers waiting for more than one key who
have not yet been notified, will get the newer value.  Further, replace will
dispatch the found event if the key is new.

=cut

sub replace {
    my ($self, %found) = @_;

    my @new_keys;

    for my $key (keys %found) {
        push @new_keys, $key unless $self->has($key);

        $self->_objects->{$key} = $found{$key};
    }

    $self->found($_) for @new_keys;
}

=item get KEY [, KEY .. ]

Fetch the value of a key.  If given a list of keys and in list context, return
the value of each key supplied as a list.

=cut

sub get {
    my ($self, @keys) = @_;

    if (@keys > 1 && wantarray) {
        return map $self->_objects->{$_}, @keys;
    }
    else {
        return $self->_objects->{$keys[0]};
    }
}

=item clear

Clear the blackboard of all values.

=cut

sub clear {
    my ($self) = @_;

    $self->_objects({});
}

=item timeout SECONDS, [ KEY, [, DEFAULT ] ]

Set a timer for N seconds to provide "default" value as a value, defaults to
`undef`.  This can be used to ensure that blackboard workflows do not reach a
dead-end if a required value is difficult to obtain.

=cut

sub timeout {
    my ($self, $seconds, $key, $default) = @_;

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

    $self->_watchers({});
}

=item clone

Create a clone of this blackboard.  This will not dispatch any events, even if
the blackboard is prepopulated.

=cut

sub clone {
    my ($self) = @_;

    my $objects   = { %{ $self->_objects } };
    my $watchers  = { %{ $self->_watchers } };
    my $interests = { %{ $self->_interests } };

    $interests->{$_} = [ @{ $interests->{$_} } ] for keys %$interests;
    $watchers->{$_}  = [ @{ $watchers->{$_}  } ] for keys %$watchers;

    return __PACKAGE__->new(
        _objects   => $objects,
        _watchers  => $watchers,
        _interests => $interests,
    );
}

=item complete



=back

=cut

return __PACKAGE__;

=head1 BUGS

None known.

=head1 LICENSE

Copyright © 2011, Say Media.
Distributed under the Artistic License, 2.0.

=cut
