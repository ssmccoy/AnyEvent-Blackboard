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

subtest "Timeout" => sub {
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

    done_testing;
};

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

subtest "Clone" => sub {
    my $blackboard = AnyEvent::Blackboard->new(
        objects => {
            key => "value",
        },
    );

    $blackboard->put(key => "value");

    my $clone = $blackboard->clone;

    ok $blackboard->get("key") eq $clone->get("key"),
        "\$blackboard and \$clone shall both have \"key\"";

    done_testing;
};

subtest "Get" => sub {
    my $blackboard = AnyEvent::Blackboard->new();

    my $value = "test";

    $blackboard->put(foo => $value);

    is $blackboard->get("foo"), $value, "Value is the same";

    done_testing;
};

subtest "Constructor, Hangup" => sub {
    plan tests => 2;

    my $blackboard = AnyEvent::Blackboard->build(
        [qw( foo )] => sub { is(shift, 1, "foo") },
        [qw( bar )] => sub { is(shift, 1, "bar") },
    )->clone;

    $blackboard->put(foo => 1);
    $blackboard->put(bar => 1);

    $blackboard->clear;
    $blackboard->hangup;

    $blackboard->put(foo => 1);
};

subtest "Remove Test" => sub {
    plan tests => 3;

    my $i = 0;
    my $blackboard = AnyEvent::Blackboard->build(
        foo => sub { is(shift, $i, "foo") },
    )->clone;

    $blackboard->put(foo => ++$i);

    $blackboard->remove("foo");

    ok ! $blackboard->has("foo"), "foo should have been removed";

    $blackboard->put(foo => ++$i);
};

subtest "Replace" => sub {
    plan tests => 1;

    my $i = 0;

    my $blackboard = AnyEvent::Blackboard->build(
        foo => sub { is(shift, $i, "foo") },
    )->clone;

    # Make sure that we only dispatch one event.
    $blackboard->replace(foo => ++$i) for 1 .. 2;
};

done_testing;
