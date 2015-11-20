# NAME

Anthill - Yet another process spawner

# VERSION

version 0.153240

# SYNOPSIS

    my $anthill = Anthill->new("sqlite-anthill.db');
        $anthill
        ->ant( 'ant#1'=> [ foo, {bar => 'baz'} ] )
        ->start_args(perl_command => {
                        worker => q{-E"say 'hello from ant!'"}
                })
        ->start
        ->wait;

# NAME

Anthill - Yet another process spawner

# FUNCTIONS

## new

Create a new Anthill.

# AUTHOR

Nicolas Georges <xlat@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Nicolas Georges.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
