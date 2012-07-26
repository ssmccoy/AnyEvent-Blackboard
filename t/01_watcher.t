#!/usr/bin/perl

package okayer;
use strict;
use warnings FATAL => "all";
use Test::More;

sub new {
    my ($class, %expect) = @_;
    bless \%expect, $class;
}

sub foo {
    my ($self, $arg) = @_;

    ok $self->{foo} eq $arg, "$self->{foo} eq $arg";
}

sub bar {
    my ($self, $arg) = @_;

    ok $self->{bar} eq $arg, "$self->{bar} eq $arg";
}

sub foobar {
    my ($self, $foo, $bar) = @_;

    ok $self->{foo} eq $foo &&
       $self->{bar} eq $bar, "both args match expect";
}


package main;
use strict;
use warnings FATAL => "all";
use Test::More;
use EV;
use AnyEvent::Blackboard;

isa_ok(AnyEvent::Blackboard->new(), "AnyEvent::Blackboard",
    "AnyEvent::Blackboard constructor");

=head1 TESTS

=over 4

=item Add Watcher

Add chains of watchers and validate they are dispatched correctly.

=cut

subtest "Add Watcher" => sub {
    plan tests => 6;

    my $blackboard = AnyEvent::Blackboard->new();
    my $okayer     = okayer->new(
        foo => "foo",
        bar => "bar",
    );

    $blackboard->watch([qw( foo bar )], [ $okayer, "foobar" ]);
    $blackboard->watch(foo => [ $okayer, "foo" ]);
    $blackboard->watch(bar => [ $okayer, "bar" ]);

    $blackboard->put(foo => "foo");
    $blackboard->put(bar => "bar");

    $blackboard->clear;

    # Put a list of keys.
    $blackboard->put(foo => "foo", bar => "bar");
};


=item Default Timeout

Time out all values by diving into the AnyEvent event loop without putting down
any events.

=cut

subtest "Default Timeout" => sub {
    my $blackboard = AnyEvent::Blackboard->new(default_timeout => 0.02);

    my $condvar = AnyEvent->condvar;

    $condvar->begin;

    $blackboard->watch(foo => sub {
            my ($foo) = @_;

            ok !defined $foo, "foo should be undefined as default";

            $condvar->end;
        });

    $condvar->recv;

    ok $blackboard->has("foo"), "foo should exist";

    done_testing;
};

=item Timeout

Timeotu a specific key with a default value.

=cut

subtest "Timeout" => sub {
    plan tests => 2;

    my $blackboard = AnyEvent::Blackboard->new();

    my $condvar = AnyEvent->condvar;

    $condvar->begin;

    $blackboard->timeout(0.01, foo => "default");

    $blackboard->watch(foo => sub {
            my ($foo) = @_;

            ok $foo eq "default", "foo should be defined as default";

            $condvar->end;
        });

    $condvar->recv;

    ok $blackboard->has("foo"), "foo should be defined";
};

=item Timeout Canceled

Verify that timeouts result in no event when a value was provided, and that
it's the value that the is available not the undef provided by default by
timeouts.

=cut

subtest "Timeout Canceled" => sub {
    my $blackboard = AnyEvent::Blackboard->new();

    my $condvar = AnyEvent->condvar;

    $condvar->begin;

    $blackboard->timeout(0.01, foo => "default");

    $blackboard->watch(foo => sub {
            my ($foo) = @_;

            ok $foo eq "provided", "foo should be defined as provided";

            $condvar->end;
        });

    $blackboard->put(foo => "provided");

    $condvar->recv;

    ok $blackboard->has("foo"), "foo should be defined";

    done_testing;
};

=item Clone

Clone the blackboard and make sure it retains its default values.

=cut

subtest "Clone" => sub {
    my $blackboard = AnyEvent::Blackboard->new();

    $blackboard->put(key => "value");

    my $clone = $blackboard->clone;

    ok $blackboard->get("key") eq $clone->get("key"),
        "\$blackboard and \$clone shall both have \"key\"";

    done_testing;
};

=item Get

Fetch a value from the blackboard without an event.

=cut

subtest "Get" => sub {
    my $blackboard = AnyEvent::Blackboard->new();

    my $value = "test";

    $blackboard->put(foo => $value);

    is $blackboard->get("foo"), $value, "Value is the same";

    done_testing;
};

=item Constructor, Hangup

Test the blackboard factory method and verify that hangup results no no events.

=cut

subtest "Constructor, Hangup" => sub {
    plan tests => 2;

    my $blackboard = AnyEvent::Blackboard->build(
        watchers => [
            [qw( foo )] => sub { is(shift, 1, "foo") },
            [qw( bar )] => sub { is(shift, 1, "bar") },
        ],
    )->clone;

    $blackboard->put(foo => 1);
    $blackboard->put(bar => 1);

    $blackboard->clear;
    $blackboard->hangup;

    $blackboard->put(foo => 1);
};

=item Remove Test

Prove that removing and re-adding a value results in a second event.

=cut

subtest "Remove Test" => sub {
    plan tests => 3;

    my $i = 0;
    my $blackboard = AnyEvent::Blackboard->build(
        watchers => [
            foo => sub { is(shift, $i, "foo") },
        ],
    )->clone;

    $blackboard->put(foo => ++$i);

    $blackboard->remove("foo");

    ok ! $blackboard->has("foo"), "foo should have been removed";

    $blackboard->put(foo => ++$i);
};

=item Replace

Prove that the replace method results in kicking off an initial event, and that
a second call to the replace method doesn't dispatch an event but updates the
value.

=cut

subtest "Replace" => sub {
    plan tests => 2;

    my $i = 0;

    my $blackboard = AnyEvent::Blackboard->build(
        watchers => [
            foo => sub { is(shift, $i, "foo") },
        ],
    )->clone;

    # Make sure that we only dispatch one event.
    $blackboard->replace(foo => ++$i) for 1 .. 2;

    is $blackboard->get("foo"), 2,
    "get results in changed value after replace";
};

=item Reentrant put

Verify that even when called reentrantly, event dispatching from put is atomic
and never creates a duplicate-dispatch condition.

=cut

subtest "Reentrant put" => sub {
    plan tests => 2;

    my $blackboard = AnyEvent::Blackboard->new;

    $blackboard->watch(foo => sub {
            my ($blackboard) = @_;

            $blackboard->put(bar => "Cause Failure");

            pass "Saw event for foo";
        }
    );

    $blackboard->watch([qw( foo bar )] => sub { pass "Saw event for foo bar" });

    $blackboard->put(foo => $blackboard);
};

=item Red herring

Verify that when hangup has happened in the middle of a dispatch loop no
further dispatching occurs.

=cut

subtest "Red herring" => sub {
    my $blackboard = AnyEvent::Blackboard->new();

    $blackboard->watch(foo => sub { $blackboard->hangup });
    $blackboard->watch(foo => sub { fail "Expected hangup" });

    $blackboard->put(foo => 1);

    # XXX This should probably move _hangup to a public-like-named method.
    ok $blackboard->_hangup, "Blackboard was hung up";

    done_testing;
};

done_testing;
