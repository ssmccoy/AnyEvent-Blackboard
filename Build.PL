#!/usr/bin/perl

use Module::Build;

my $build = Module::Build->new(
    module_name => "Blackboard",
    requires    => {
        AnyEvent => 0,
        Moose    => 0
    },
);

$build->create_build_script;
