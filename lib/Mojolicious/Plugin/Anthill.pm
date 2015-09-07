package Mojolicious::Plugin::Anthill;
# VERSION
# ABSTRACT: Anthill plugin for Mojolicious
use Mojo::Base 'Mojolicious::Plugin';
 
use Anthill;

sub register {
	my ($self, $app, $conf) = @_;
	#TODO: when we will have commands to manage anthill and ants
	#~ push @{$app->commands->namespaces}, 'Anthill::Command';
	$cfg->{app} = $app;
	my $anthill = Anthill->new($conf);
	$app->helper(anthill => sub {$anthill});
}
 
1;