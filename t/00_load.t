use Modern::Perl;
use Test::More;

BEGIN {
    use_ok( 'Anthill' ) || print "Bail out!\n";
}

diag( "Testing Anthill $Anthill::VERSION, Perl $], $^X" );

done_testing();
