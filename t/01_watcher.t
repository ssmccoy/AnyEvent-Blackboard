#!/usr/bin/perl

use Test::More;
use Blackboard;

package okayer;
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

plan tests => 2;

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

    plan tests => 3;

    $blackboard->put(foo => "foo");
    $blackboard->put(bar => "bar");
};
