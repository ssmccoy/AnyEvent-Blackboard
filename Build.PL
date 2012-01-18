#!/usr/bin/perl

use Module::Build;

my $build = Module::Build->new(
    module_name => "Blackboard",
    dist_version => 0.01,
    requires    => {
        AnyEvent => 0,
        Mouse    => 0
    },
);

$build->create_build_script;
