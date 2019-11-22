use Modern::Perl;
use Test::More;

use_ok('Anthill');

my $db = $ENV{TEST_DBI} || 'temp.db';
my $dbq = $db =~ s/'/\\'/gr;	#escape quotes
my $is_sqlite = $db =~ /\.db$/;
unlink $db if $is_sqlite && -e $db;

my $anthill = Anthill->new({ dbh => $db });
is ref($anthill), 'Anthill', 'new Anthill';
my $dbh = $anthill->dbh;
is ref($dbh), 'DBI::db', 'anthill db handle';
#deploying
if ($is_sqlite) {
  ok $dbh->do( Anthill->deploy_script( $dbh ) ), 'deploy anthill';
} else {
  eval {
    $dbh->do(q/if OBJECT_ID('anthill.ant') is not null drop table anthill.ant/);
    $dbh->do(q/if SCHEMA_ID('anthill') is not null drop schema anthill/);
    foreach my $req (grep $_, split /\bgo\b/, Anthill->deploy_script( $dbh )) { 
      note('executing: ' . $req);
      $dbh->do( $req );
    }
  };
  is "$@", '', 'deploy anthill';
}
#spawn an ant and retrieve it's ID
my $ant = $anthill->ant( 'my ant#1' => [42] );
is ref($ant), 'Anthill::Ant', 'new ant';
my $id = $ant->id;
is $id, 1, 'ant id';
$ant->start_args( perl_command => {
			worker => qq^-MAnthill -Ilib -E"\$a=Anthill->new('$dbq');\$a->ant($id)->result(32)->finish;say 'hello from ant!'"^,
			#~ debug => 1,
		});
is $ant->name, 'my ant#1', 'ant name';
is $ant->pid, undef, 'ant pid';

#starting ant
is_deeply $ant->start, $ant, 'start ant';
ok $ant->pid, 'ant pid';
is_deeply $ant->args, [42], 'ant args';
$ant->result({foo => 'bar'});
is_deeply $ant->result, { foo => 'bar' }, 'ant result';

$ant->wait();

#creating other ants
$anthill->ant( 'my ant#99'.$_ => [ $_ ] ) for 1..4;
#querying ants
my @ants = $anthill->ants( state => [ 'inactive', 'finished' ], args => {like => ($is_sqlite ? '[4%' : '[[]4%') } );
is scalar @ants, 2, "list ants using filters";

$dbh->disconnect;
unlink $db if $is_sqlite;
done_testing;