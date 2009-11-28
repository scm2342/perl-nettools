#! /usr/bin/perl

$|=1;

use strict;
use warnings;
use IO::Socket;
use IO::Select;
use bytes;

my ($bind, $port, $user, $password, $conback, $conport, undef) = @ARGV;

die "Usage:\n\tsocks.pl bindaddr port user password (conback) (conport)\n\tbindaddr = bind adress\n\tport = bind port\n\tuser = password auth user\n\tpassword = password auth password\n\toptional: conback = connect back ip\n\toptional: conport = connect back port\n" if not ($bind and $port and $user and $password) or ($conback and not $conport); #todo check for validity

sub fh_stdio()
{
	return \*STDIN, \*STDOUT;
}

sub fh_conn()
{
	my ($address, $port) = @_;
	my $socket = IO::Socket::INET->new(	PeerAddr => $address,
						PeerPort => $port)
							or die "Could not connect to ".$address." on port ".$port."\n";
	return $socket, $socket;
}

sub fh_listen()
{
	my ($bindip, $bindport) = @_;
	my $socket = IO::Socket::INET->new(	Listen => 1,
						LocalAddr => $bindip,
						LocalPort => $bindport,
						Proto => 'tcp',
						Reuse => 1)
							or die "Could not open socket on ".$bindip." on port ".$bindport."\n";
	my $newsocket = $socket->accept();
	return $newsocket, $newsocket;
}


sub relay()
{
	my ($inhandle, $outhandle, $inhandle2, $outhandle2) = @_;
	my $sel = IO::Select->new([$inhandle, $outhandle2], [$inhandle2, $outhandle]);
	SELECT: while(my @ready = $sel->can_read())
	{
		foreach my $handle (@ready)
		{
			&io($$handle[0], $$handle[1]) or last SELECT;
		}
	}
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

sub nego_pass()
{
	my ($inhandle, $outhandle) = @_;
	syswrite($outhandle, (pack("C", 2))[0]) or die "fuck";
	return 0;
}

sub req()
{
	my ($inhandle, $outhandle) = @_;
	my $buf;
	sysread($inhandle, $buf, 4) or die "fuck";
	my ($version, $command, $reserved, $addresstype) = unpack("C4", $buf);
	print "ver: " . $version . " cmd: " . $command . " res: " . $reserved . " atyp: " . $addresstype . "\n";
	my ($address, $port);
	if($addresstype == 1)
	{
		sysread($inhandle, $buf, 4) or die "fuck";
		$address = join('.', unpack("C4", $buf));
		sysread($inhandle, $buf, 2) or die "fuck";
		$port = unpack("n", $buf);
		print "ip: " . $address . " port: " . $port . "\n";
	}
	elsif($addresstype == 2)
	{
		#domain
	}
	elsif($addresstype == 3)
	{
		#ipv6
	}
	else
	{
		die "fuck";
	}
	return $command, $address, $port;
	&connect()
}

#first select
sub negotiate()
{
	my ($inhandle, $outhandle) = @_;
	my $buf;
	my @methods;

	sysread($inhandle, $buf, 2) or die "fuck";
	my ($version, $nmethods) = unpack("C2", $buf);
	sysread($inhandle, $buf, $nmethods) or die "fuck";
	@methods = unpack("C" . $nmethods, $buf);
	
	if(grep {$_ == 0} @methods)
	{
		syswrite($outhandle, pack("C2", (5,0))) or die "fuck";
		return 1;
	}
	elsif(grep {$_ == 2} @methods)
	{
		return &nego_pass($inhandle, $outhandle);
	}
	else
	{
		syswrite($outhandle, pack("C", 255)) or die "fuck";
	}
	return 0;
}

my ($ihandle, $ohandle) = &fh_listen("127.0.0.1", 1080);
if(&negotiate($ihandle, $ohandle))
{
	my ($command, $address, $port) = &req($ihandle, $ohandle);
	if($command == 1)
	{
		my ($inhandle2, $outhandle2) = &fh_conn($address, $port);
		syswrite($ohandle, pack("C10", (5,0,0,1,0,0,0,0,0,0))) or die "fuck";
		&relay($ihandle, $ohandle, $inhandle2, $outhandle2);
	}
}
