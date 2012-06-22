#!/usr/bin/env perl

use strict;
use warnings FATAL => "all";
use Test::More;
use Benchmark qw( :all );
use AnyEvent::Blackboard;

my $blackboard = AnyEvent::Blackboard->build(
    watch => [ test => \&pass ]
);

sub rate {
    my ($benchmark) = @_;
    # This copies some funk from the Benchmark internals, which I should say
    # are not particularly legible.
    my ($r, $pu, $ps, $cu, $cs, $n) = @$benchmark;

    my $elapsed = $cu + $cs + $pu + $ps;

    return $n / $elapsed;
}


subtest "Dispatch" => sub {
    my $benchmark = timeit 100_000, sub {
        $blackboard->clone->put(test => 1);
    };

    my $rate = rate($benchmark);

    ok $rate > 30000, "Rate of $rate is above 30,000/second";
};

done_testing;
