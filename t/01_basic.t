use Modern::Perl;
use Test::More;

use_ok('Anthill');

my $db ='temp.db';
unlink $db if -e $db;
my $anthill = Anthill->new({ dbh => $db });
is ref($anthill), 'Anthill', 'new Anthill';
my $dbh = $anthill->dbh;
is ref($dbh), 'DBI::db', 'anthill db handle';
#deploying
ok $dbh->do( Anthill->deploy_script( $dbh ) ), 'deploy anthill';
#TODO: spawn an ant and retrieve it's ID
my $ant = $anthill->ant( 'my ant#1' => [42] );
is ref($ant), 'Anthill::Ant', 'new ant';
my $id = $ant->id;
is $id, 1, 'ant id';
$ant->start_args( perl_command => {
			worker => qq^-MAnthill -Ilib -E"\$a=Anthill->new('temp.db');\$a->ant($id)->result(32);say 'hello from ant!'"^,
			#~ worker => q^-E"say 'hello from ant!'"^,
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
$dbh->disconnect;
unlink $db;
done_testing;