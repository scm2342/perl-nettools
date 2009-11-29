#! /usr/bin/perl

$|=1;

use strict;
use warnings;
use IO::Socket;
use IO::Select;
use bytes;

my ($bind, $port, $user, $password, $conback, $conport, undef) = @ARGV;

die "Usage:\n\tsocks.pl bindaddr port user password (conback) (conport)\n\tbindaddr = bind adress\n\tport = bind port\n\tuser = password auth user\n\tpassword = password auth password\n\toptional: conback = connect back ip\n\toptional: conport = connect back port\n" if not ($bind and $port and $user and $password) or ($conback and not $conport); #todo: check for validity

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
	return $socket;
}

sub readbytes()
{
	my ($inhandle, $numbytes) = @_;
	my $buf;
	sysread($inhandle, $buf, $numbytes) == $numbytes or die "could not read enough bytes to fullfill requirement of " . $numbytes . "\n";
	return $buf;
}

sub getbytes()
{
	my ($inhandle, $numbytes) = @_;
	my $buf = &readbytes($inhandle, $numbytes);
	return unpack("C" . $numbytes, $buf);
}

sub getuint16()
{
	my ($inhandle) = @_;
	my $buf = &readbytes($inhandle, 2);
	return unpack("n", $buf);
}

sub getip()
{
	my ($inhandle) = @_;
	my $buf = &readbytes($inhandle, 4);
	my @ip = unpack("C4", $buf);
	return join(".", @ip);
}

sub getstring()
{
	my ($inhandle) = @_;
	my ($length) = &getbytes($inhandle, 1);
	print "strlen: " . $length . "\n";
	my $buf = &readbytes($inhandle, $length);
	return unpack("a" . $length, $buf);
}

sub sendbytes()
{
	my ($outhandle, $bytes) = @_;
	syswrite($outhandle, $bytes) == length($bytes) or die "could not send enough bytes to fullfull requirement of " . length($bytes) . "\n";
}

sub setbytes()
{
	my ($outhandle, @bytes) = @_;
	my $bytes = pack("C" . ($#bytes + 1), @bytes);
	&sendbytes($outhandle, $bytes);
}

sub setuint16()
{
	my ($outhandle, @ints) = @_;
	my $bytes = pack("n" . ($#ints + 1), @ints);
	&sendbytes($outhandle, $bytes);
}

sub setip()
{
	my ($outhandle, $ip) = @_;
	my $bytes = pack("C4", split('.', $ip));
	&sendbytes($outhandle, $bytes);
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

sub req()
{
	my ($inhandle, $outhandle) = @_;
	my ($version, $command, $reserved, $addresstype) =  &getbytes($inhandle, 4);
	print "ver: " . $version . " cmd: " . $command . " res: " . $reserved . " atyp: " . $addresstype . "\n";
	my ($address, $port);
	if($addresstype == 1)
	{
		$address = &getip($inhandle);
		$port = &getuint16($inhandle);
		print "ip: " . $address . " port: " . $port . "\n";
	}
	elsif($addresstype == 3)
	{
		$address = &getstring($inhandle);
		$port = &getuint16($inhandle);
		print "dns: " . $address . " port: " . $port . "\n";
	}
	elsif($addresstype == 4)
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

sub negotiate()
{
	my ($inhandle, $outhandle) = @_;

	my ($version, $nmethods) = &getbytes($inhandle, 2);
	my @methods = &getbytes($inhandle, $nmethods);
	
	if(grep {$_ == 0} @methods)
	{
		&setbytes($outhandle, (5,0));
		return 1;
	}
	elsif(grep {$_ == 2} @methods)
	{
		return &nego_pass($inhandle, $outhandle);
	}
	else
	{
		&setbytes($outhandle, (255));
	}
	return 0;
}

sub nego_pass()
{
	my ($inhandle, $outhandle) = @_;
	&setbytes($outhandle, (2));
	return 0;
}

sub handle_conn()
{
	my ($socket) = @_;
	if(&negotiate($socket, $socket))
	{
		my ($command, $address, $port) = &req($socket, $socket);
		if($command == 1)
		{
			my ($inhandle2, $outhandle2) = &fh_conn($address, $port);
			&setbytes($socket, (5,0,0,1,0,0,0,0,0,0));
			&relay($socket, $socket, $inhandle2, $outhandle2);
			$inhandle2->close();
		}
	}
	$socket->close();
}

my $listensocket = &fh_listen($bind, $port);
my $newsock;
while(1)
{
	$newsock = $listensocket->accept();
	print "Accepting con\n";
	my $child = fork();
	last if($child);
}

print "hello im a child\n";
&handle_conn($newsock);
print "hello im a child and my life is over...\n";
