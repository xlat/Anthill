package Anthill;
# VERSION

# ABSTRACT: Yet another process spawner
use Modern::Perl;
use DBIx::Simple;
use SQL::Abstract;
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
create table if not exists ant(
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
				last_id => q{select last_insert_rowid() as id},
				select  => q{select ${field} from ant where id = ${id}},
				update  => q{update ant set ${field}='${value}' where id = '${id}'},
				list    => q{select id from ant ${where} order by id desc},
			},
			ado => {
				deploy  => <<'DEPLOY',
if SCHEMA_ID('anthill') is null 
begin
	exec sp_executesql N'create schema anthill AUTHORIZATION [${owner}]';
end	
go
if OBJECT_ID('anthill.ant') is null
begin
create table anthill.ant(
	id int not null identity primary key,
	name nvarchar(200) not null,
	state varchar(10) not null default 'inactive',
	args nvarchar(max) null,
	start_args nvarchar(max) null,
	result nvarchar(max) null,
	pid int null
);
end
go
DEPLOY
				insert  => q{insert into anthill.ant(name, args, start_args) values('${name}','${args}','${start_args}')},
				# using SCOPE_IDENTITY() instead of IDENT_CURRENT() to prevent races between different sessions
				last_id => q{select SCOPE_IDENTITY() as id},
				select  => q{select ${field} from anthill.ant where id = ${id}},
				update  => q{update anthill.ant set ${field}='${value}' where id = '${id}'},
				list	=> q{select id from anthill.ant ${where} order by id desc},
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
		if(ref $param_value){
			$param_value = $$param_value;
		}
		else{
			$param_value =~ s/'/''/g;
		}
		$sql =~ s/\$\{$param_name\}/$param_value/g;
	}
	$sql;
}

sub app{ shift->{app} }
sub dbh{ 
	my $dbh = shift->{dbh};
	if(ref $dbh eq 'CODE'){
		$dbh = $dbh->();
	}
	$dbh;
}
sub dbixs{ 
	my $self = shift;
	if(ref $self->{dbh} eq 'CODE') {
		#always rebuild object in case dbh has changed
		#and keep a reference
		return $self->{dbixs} = DBIx::Simple->new( $self->dbh );
	}	
	$self->{dbixs} //= DBIx::Simple->new( $self->dbh );
}

sub ant{ #return an existing Anthill::Ant object or create a new one
	new Anthill::Ant( @_ );
}

sub ants{#return a list of Anthill::Ant objects matching filters given in arguments
	my ($self, %filters) = @_;
	my $where = "";
	my @binds;
	if(%filters){
		my $sql_abstract = SQL::Abstract->new;
		($where ,@binds) = $sql_abstract->where( \%filters );
		#manually interpolate where for ADO & MSS
		s/'/''/g for @binds;
		s/(.*)/'$1'/ for @binds;
		$where =~ s/\?/shift(@binds)/ge;
		@binds = ();
	}
	my $sql = $self->sql(list => { where => \$where });
	my @ants = map{ $self->ant($_) } 
			   $self->dbixs->query($sql, @binds)->flat;
	return @ants;
}

sub deploy_script{
	my $class = shift;
	my $dbh = shift;
	my $owner = shift // 'dbo';
	my $driver = $dbh->{Driver}{Name};
	return $class->new({dbh=>$dbh})
				 ->sql(deploy => { owner => $owner });
}

1;
__END__
=head1 NAME

Anthill - Yet another process spawner

=cut

=head1 SYNOPSIS

    my $anthill = Anthill->new('sqlite-anthill.db');
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
