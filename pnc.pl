#! /usr/bin/perl

#Netcat like Perl Script
#Sven Mattsen
#
#Intended use is chaining ssh:
#suppose G is a computer where you have an account and that you can reach via ssh and that not nessesarily allows tcp forwarding.
#further more A is the computer you want to reach through G.
#sadly G has no netcat and no socat or something similar installed. but it has perl installed.
#now you could use this script as follows:
#upload this script
#scp pnc <username>@G:
#invoke ssh:
#ssh -o ProxyCommand="ssh <username>@G perl pnc %h %p" <username>@A

use strict;
use warnings;
use IO::Select;
use IO::Socket;

die("Usage\n\tpnc host port\n") if(!defined($ARGV[0]) or $ARGV[0] =~ /[[:blank:]]/ or !defined($ARGV[1]) or $ARGV[1] !~ /^[0-9]+$/ or $ARGV[1] > 65535 or $ARGV[1] < 0);

my ($addr, $port, undef) = @ARGV;

my $SH = &connect($addr, $port);

my $sel = IO::Select->new([\*STDIN, $SH], [$SH, \*STDOUT]);
SELECT: while(my @ready = $sel->can_read())
{
	foreach my $handle (@ready)
	{
		&io($$handle[0], $$handle[1]) or last SELECT;
	}
}

sub connect()
{
	my ($addr, $port) = @_;
	my $socket = IO::Socket::INET->new(	PeerAddr => $addr,
						PeerPort => $port)
		or die "Could not connect to ".$addr.":".$port."!\n";
	return $socket;
}

sub io()
{
	my ($inhandle, $outhandle) = @_;
	my ($buf, $length, $offset, $bytes) = ("", 0, 0, 0);
	$length = sysread($inhandle, $buf, 4096, $offset) or return 0;
	while($length)
	{
		$bytes = syswrite($outhandle, $buf, $length, $offset) or return 0;
		$offset += $bytes;
		$length -= $bytes;
	}
	return 1;
}
