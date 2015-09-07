package Anthill::Ant;
# VERSION
# ABSTRACT: Anthill::Ant object
use Modern::Perl;
use Win32;
use Win32::Process;
use Try::Tiny;
use Mojo::JSON qw(encode_json decode_json);
use Cwd qw(cwd);
#TODO: allow to spawn a command OR a callback ( need to be registered to the plugin )
#	+ Maximize separation bertween Ant and command/callback for job->finish/fail
#	+ wrap within try/catch
#	++ add ENV variable to share ANT infos:
#	++ ANT_ID, ...
sub new{
	my ($class, $anthill) = (shift, shift );
	if(@_ == 1 ){
		#rebuild an existing Ant by ID
		my $id = shift;
		my $self = bless { anthill => $anthill, id => $id }, $class;
		return $self if $self->state;
		return;
	}
	my ( $name, $args, @start_args) = @_;
	$args = encode_json($args);
	my $start_args = encode_json(\@start_args);
	my $self = bless { anthill => $anthill }, $class;
	#insert an ant in database and retrieve it's ID
	$self->query(insert => { 
			name => $name, 
			args => $args,	#the effective ant arguments 
			start_args => $start_args, #the way the ant is spawned
		});
	$self->{id} = $self->query( 'last_id' )->list;
	$self;
}

sub anthill{ shift->{anthill} }

sub app{ shift->{anthill}{app} }

sub query{
	my $self = shift;
	my $result = scalar $self->anthill->dbixs->query($self->anthill->sql(@_));
	return $result;
}

sub _set_field{
	my ($self, $field, $value, $is_json) = @_;
	if ($is_json) {
		$value = encode_json($value);
	}
	$self->query(update => { 
			field => $field, 
			value => $value, 
			id => $self->id 
		});
	$self;
}

sub _get_field{
	my ($self, $field, $is_json) = @_;
	my $value = $self->query(select => { 
			field => $field, 
			id => $self->id 
		})->list;
	$value = decode_json($value) if $is_json && defined $value;
	$value;
}

sub _field{ #get/set ant field
	my ($self, $field, $is_json, $value) = @_;
	if (@_ == 4) {
		return $self->_set_field($field => $value, $is_json);
	}
	$self->_get_field($field, $is_json);
}

sub info{ #return an hashref with infos: state, args, result, pid, id
	my $self = shift;
	return unless $self->{id};
	return {
		state => $self->state,
		args => $self->args,
		result => $self->result,
	};        
}

sub start{
	my ($self) = @_;
	my $start_args = $self->start_args;
	#change ant state as active
	if ($start_args && ref $start_args eq 'ARRAY') {
		$self->state('active');
		if(my $pid = $self->spawn( @$start_args )){
			$self->pid( $pid );
		}
		else{
			$self->fail;
		}
	}
	$self;
}
sub state{ #get/set ant state
	shift->_field('state',0, @_);
}
sub name{ #get/set ant name
	shift->_field('name',0, @_);
}
sub pid{ #get/set ant pid
	shift->_field('pid',0, @_);
}
sub id{ #get ant id
	shift->{id};
}
sub args{ #get/set ant args
	shift->_field('args',1, @_);
}
sub start_args{ #get/set ant start_args
	my $self = shift;
	@_ = [ @_ ] if @_;
	$self->_field('start_args',1, @_);
}
sub result{ #get/set ant result
	shift->_field('result',1, @_);
}
sub finish{ #change ant state as finished
	my $self = shift;
	$self->state('finished');
	if( my $result = shift ){
		$self->set_field( result => encode_json($result) );    
	}
}
sub fail{ #change ant state as failed
	my $self = shift;
	$self->state('failed');
	if( my $result = shift ){
		$self->set_field( result => encode_json($result) );    
	}
}

sub spawn{
    my ($self, $type, $args) = @_;
	if($type eq 'perl_command'){
		my $commands = delete $args->{params} // ['',[]];
		my $command = $commands->[0];
		my $arguments = $commands->[1];
		return $self->spawn_perl_command($command, $arguments, $args);
	}
	elsif($type eq 'command'){
		my $commands = delete $args->{params} // ['',[]];
		my $command = $commands->[0];
		my $arguments = $commands->[1];
		return $self->spawn_command($command, $arguments, $args);
	}
	#TODO... 
	#spawning a callback will be a special form of a perl_command,
	# that will recall worker => $0 with arguments 
	#	[ anthill => callback => $cb_name ]
	#Require to implement an 'anthill' command and 'callback' sub-command.
	die "spawn type '$type' not implemented yet!";
}

sub spawn_command{
	my ($self, $command, $arguments, $conf) = @_;
	$arguments //= [];
	$conf //= {};
	my $debug = $conf->{debug};
    my $pid;
    try{
        my $ant_id = $self->id;
		my $title = $conf->{title} // 'Ant %name% - %id%';
		{
			my $name = $self->name;
			$title =~ s/\%name%/$name/g;
			$title =~ s/\%id%/$ant_id/g;
		}
        my $full_command = qq{"$command"} . 
							join (' ', @$arguments);
        if ($debug && $self->app) {
            $self->app->log->debug("Spawning a command:\n".
            "command:`$command`\ncommand line: `$full_command`");
        }
        $pid = Win32::Process::Create( 
            my $process, 
            $command,
            $full_command,
            0, 
            #DETACHED_PROCESS ||
            #CREATE_NEW_CONSOLE ||
            #CREATE_NO_WINDOW ||
            NORMAL_PRIORITY_CLASS, 
            $conf->{path} // cwd(),
        );
        if($pid){
			$self->{process_object} = $process;
            $pid = $process->GetProcessID;
			if($self->app){
				$self->app->log->debug("[pid: $pid] ant $ant_id for '$command' just created");
			}
        }
        elsif($self->app){
            $self->app->log->error("Could not spawn a command:\n".
                "command:`$command`\ncommand line: `$full_command`\nError: " .
                Win32::FormatMessage(Win32::GetLastError()) );
        }
    }
    catch{
        say "Command spawn error: $_";
    };
    return $pid;
}

sub spawn_perl_command{
	my ($self, $command, $arguments, $conf) = @_;
	$arguments //= [];
	$conf //= {};
    my $worker_script = $conf->{worker} // $0;
	$worker_script = '"'.$worker_script.'"' 
		unless index($worker_script,'"')>=0;
	my $debug = $conf->{debug};
    my $pid;
    try{
		#because Mojolicious application will just do "something else: ~psgi" in plack_env
        local $ENV{PLACK_ENV}=undef;
        my $cmd = $ENV{ComSpec} || "$ENV{WINDIR}\\system32\\cmd.EXE";
        my $cmd1 = $debug ? $cmd : $^X;
        my $ant_id = $self->id;
		my $title = $conf->{title} // 'Ant %name% - %id%';
		{
			my $name = $self->name;
			$title =~ s/\%name%/$name/g;
			$title =~ s/\%id%/$ant_id/g;
		}
        my $cmd2 = $debug 
				? "$cmd /C start \"$title\" \"$^X\" -d" 
				: $^X;
        my $full_command = qq{$cmd2 $worker_script } . 
							join (' ', $command, @$arguments);
        if ($debug && $self->app) {
            $self->app->log->debug("Spawning a '$command' perl command:\n".
            "command:`$cmd1`\ncommand line: `$full_command`");
        }
        $pid = Win32::Process::Create( 
            my $process, 
            $cmd1,
            $full_command,
            0, 
            #DETACHED_PROCESS ||
            #CREATE_NEW_CONSOLE ||
            #CREATE_NO_WINDOW ||
            NORMAL_PRIORITY_CLASS, 
            $conf->{path} // cwd(),
        );
        if($pid){
			$self->{process_object} = $process;
            $pid = $process->GetProcessID;
			if($self->app){
				$self->app->log->debug("[pid: $pid] ant $ant_id for '$command' just created");
			}
        }
        elsif($self->app){
            $self->app->log->error("Could not spawn a '$command' perl command:\n".
                "command:`$cmd`\ncommand line: `$full_command`\nError: " .
                Win32::FormatMessage(Win32::GetLastError()) );
        }
    }
    catch{
        say "Perl command spawn error: $_";
    };
    return $pid;
}

#Win32::Process management shortcuts
sub _get_process_object{
	my $self = shift;
	return $self->{process_object}
		if exists $self->{process_object};
	Win32::Process::Open(my($process), $self->pid, my $iflags)
	or return;
	return $process unless wantarray;
	return ($process, $iflags);
}

sub wait{
	my $self = shift;
	my $process = $self->_get_process_object 
		or return $self;
	$process->Wait( shift // INFINITE );
	$self;
}

sub still_active{
	my $self = shift;
	my $process = $self->_get_process_object or return;
	$process->GetExitCode(my $exitcode);
	$exitcode == Win32::Process::STILL_ACTIVE();
}

#Resume / Suspend (may not works with re-attached Ant(need to keep track of original $process object)
sub resume{
	my $self = shift;
	unless(exists $self->{process_object}){
		warn "Resume may not works with an re-attached object, see perldoc Win32::Process";
	}
	$self->_get_process_object->Resume;
}

sub suspend{
	my $self = shift;
	unless(exists $self->{process_object}){
		warn "Suspend may not works with an re-attached object, see perldoc Win32::Process";
	}
	$self->_get_process_object->Suspend;
}

sub kill{
	my $self = shift;
	#~ my $process = $self->_get_process_object or return;
	#~ $process->Kill( my $exitcode );
	my $pid = shift || $self->pid;
	Win32::Process::KillProcess( $pid, my $exitcode );
	return $exitcode;
}

sub exitcode{
	my $self = shift;
	my $process = $self->_get_process_object or return;
	$process->GetExitCode( my $exitcode );
	return $exitcode;
}

1;