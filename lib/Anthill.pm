package Anthill;
# VERSION
# ABSTRACT: Yet another process spawner
use Modern::Perl;
use DBIx::Simple;
use Anthill::Ant;

sub new{
	my ($class, $cfg ) = @_;
	#syntaxic sugar new("dbi:...:...") or new("anthill.db");
	$cfg = { dbh => $cfg } 
		if !ref($cfg) and $cfg;
	die 'Usage Anthill->new({ dbh => $dbh, app => $app})' unless ref($cfg) eq 'HASH';
	if(!ref $cfg->{dbh}){
		my $dbi = $cfg->{dbh};
		$dbi = "dbi:SQLite:$dbi"
			unless index($dbi,':')>0;
		$cfg->{dbh} = DBI->connect( $dbi );
	}
	elsif(ref($cfg->{dbh}) eq 'ARRAY'){
		$cfg->{dbh} = DBI->connect( @{$cfg->{dbh}} );
	}
	my $self = bless $cfg, 'Anthill';
	
	#choose SQLS set matching our driver
	if($self->dbh){
		my $DRIVER = lc $self->dbh->{Driver}{Name};
		#TODO: check for deploy requirement (existance of ant table)
		#dirty: no bidnd_param '?' because of DBD::ADO buggy driver with binding parameters.
		$self->{sqls} = {
			sqlite => {
				deploy  => <<'DEPLOY',
create table ant(
	id integer not null primary key autoincrement,
	name nvarchar(200) not null,
	state varchar(10) not null default 'inactive',
	args text null,
	start_args text null,
	result text null,
	pid integer null
);
DEPLOY
				insert  => q{insert into ant(name, args, start_args) values('${name}','${args}','${start_args}')},
				last_id => q{select id from ant order by id desc limit 1},
				select  => q{select ${field} from ant where id = ${id}},
				update  => q{update ant set ${field}='${value}' where id = '${id}'},
			},
			ado => {
				deploy  => <<'DEPLOY',
create schema anthill AUTHORIZATION ${owner};
go
create table anthill.ant(
	id int not null identity primary key,
	name nvarchar(200) not null,
	state varchar(10) not null default 'inactive',
	args nvarchar(max) null,
	start_args nvarchar(max) null,
	start_args nvarchar(max) null,
	result nvarchar(max) null,
	pid int null
);
go
DEPLOY
				insert  => q{insert into ant(name, args, start_args) values('${name}','${args}','${start_args}')},
				last_id => q{select top 1 id from anthill.ant order by id desc},
				select  => q{select ${field} from anthill.ant where id = ${id}},
				update  => q{update anthill.ant set ${field}='${value}' where id = '${id}'},
			}
		}->{$DRIVER} 
		or die "Could not find SQL for your driver '$DRIVER'";
	}
	
	$self;
}

sub sql{
	my ($self, $cmd, $binds) = @_;
	my $sql = $self->{sqls}{$cmd} 
		or die "unknow sql command '$cmd'!";
	while(my($param_name, $param_value) = each %$binds){
		$param_value =~ s/'/''/g;
		$sql =~ s/\$\{$param_name\}/$param_value/g;
	}
	$sql;
}

sub app{ shift->{app} }
sub dbh{ shift->{dbh} }
sub dbixs{ 
	my $self = shift;
	$self->{dbixs} //= DBIx::Simple->new( $self->{dbh} );
}

sub ant{ #return an existing Anthill::Ant object or create a new one
	new Anthill::Ant( @_ );
}

sub deploy_script{
	my $class = shift;
	my $dbh = shift;
	my $owner = shift // 'dbo';
	my $driver = $dbh->{Driver}{Name};
	return $class
					->new({dbh=>$dbh})
					->sql(deploy => { owner => $owner });
}

1;
__END__
=head1 NAME

Anthill - Yet another process spawner

=cut

=head1 SYNOPSIS

    my $anthill = Anthill->new("sqlite-anthill.db');
	$anthill
	->ant( 'ant#1'=> [ foo, {bar => 'baz'} ] )
	->start_args(perl_command => {
			worker => q{-E"say 'hello from ant!'"}
		})
	->start
	->wait;

=head1 FUNCTIONS

=head2 new

Create a new Anthill.

=cut
