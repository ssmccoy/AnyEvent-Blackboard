package AnyEvent::Blackboard;

=head1 NAME

AnyEvent::Blackboard - An extension of Async::Blackboard which uses AnyEvent
for timeouts.

=head1 SYNOPSIS

  my $blackboard = AnyEvent::Blackboard->new();

  $blackboard->watch([qw( foo bar )], [ $object, "found_foobar" ]);
  $blackboard->watch(foo => [ $object, "found_foo" ]);

  # After 250ms, provide ``undef'' for ``foo''
  $blackboard->timeout(foo => 0.25);

=head1 RATIONALE

Async::Blackboard makes a fantastic synchronization component -- however, it
does have the possible condition of allowing control to be abandoned due to a
lack value.  This subclass adds the functionality of timeouts on keys to ensure
this doesn't happen.

=cut

use strict;
use warnings FATAL => "all";

use AnyEvent;
use Mouse;

extends qw( Async::Blackboard );

our $VERSION = 0.4.0;

=head1 ATTRIBUTES

=over 4

=cut

=item default_timeout -> Num

Default timeout in (optionally fractional) seconds.

=cut

has default_timeout => (
    is         => "ro",
    isa        => "Num",
    default    => 0,
);

=back

=cut

no Mouse;

=back

=head1 METHODS

=over 4

=item timeout SECONDS, [ KEY, [, DEFAULT ] ]

Set a timer for N seconds to provide "default" value as a value, defaults to
`undef`.  This can be used to ensure that blackboard workflows do not reach a
dead-end if a required value is difficult to obtain.

=cut

sub timeout {
    my ($self, $seconds, $key, $default) = @_;

    unless ($self->has($key)) {
        my $guard = AnyEvent->timer(
            after => $seconds,
            cb    => sub {
                $self->put($key => $default) unless $self->has($key);
            }
        );

        # Cancel the timer if we find the object first (otherwise this is a NOOP).
        $self->_watch([ $key ], sub { undef $guard });
    }
}

=item watch KEYS, WATCHER [, KEYS, WATCHER ]

=item watch KEY, WATCHER [, KEYS, WATCHER ]

Overrides L<Async::Blackboard> only for the purpose of adding a timeout.

=cut

sub watch {
    my ($self, @args) = @_;

    confess "Expected balanced as arguments" if @args % 2;

    if ($self->default_timeout) {
        my $timeout = $self->default_timeout;
        my @keys    = keys %{ { @args } };

        for my $key (@keys) {
            $self->timeout($timeout, $key);
        }
    }

    return $self->SUPER::watch(@args);
}


=item clone

Create a clone of this blackboard.  This will not dispatch any events, even if
the blackboard is prepopulated.

=cut

sub clone {
    my ($self) = @_;

    my $class = ref $self || __PACKAGE__;

    my $default_timeout = $self->default_timeout;

    my $clone = $self->SUPER::clone;

    # This is a little on the side of evil...we're not supposed to know where
    # this value is stored.
    $clone->{default_timeout} = $default_timeout;

    # Add timeouts for all current watcher interests.  The timeout method
    # ignores keys that are already defined.
    if ($default_timeout) {
        for my $key ($clone->watched) {
            $clone->timeout($default_timeout, $key);
        }
    }

    return $clone;
}

return __PACKAGE__;

=back

=head1 BUGS

None known.

=head1 LICENSE

Copyright © 2011, Say Media.
Distributed under the Artistic License, 2.0.

=cut
