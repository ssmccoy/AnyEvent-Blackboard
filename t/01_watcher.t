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
use Blackboard;

isa_ok(Blackboard->new(), "Blackboard", "Blackboard constructor");

subtest "Add Watcher" => sub {
    my $blackboard = Blackboard->new();
    my $okayer     = okayer->new(
        foo => "foo",
        bar => "bar",
    );

    $blackboard->watch([qw( foo bar )], [ $okayer, "foobar" ]);
    $blackboard->watch(foo => [ $okayer, "foo" ]);
    $blackboard->watch(bar => [ $okayer, "bar" ]);

    $blackboard->put(foo => "foo");
    $blackboard->put(bar => "bar");

    done_testing;
};

subtest "Timeout" => sub {
    my $blackboard = Blackboard->new();

    my $condvar = AnyEvent->condvar;

    $condvar->begin;

    $blackboard->timeout(foo => 0.01, "default");

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
    my $blackboard = Blackboard->new();

    my $condvar = AnyEvent->condvar;

    $condvar->begin;

    $blackboard->timeout(foo => 0.15, "default");

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

done_testing;
