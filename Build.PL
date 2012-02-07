#!/usr/bin/perl

use Module::Build;

my $build = Module::Build->new(
    module_name => "AnyEvent::Blackboard",
    version_from => "AnyEvent::Blackboard",
    requires    => {
        AnyEvent => 0,
        Mouse    => 0
    },
);

$build->create_build_script;
