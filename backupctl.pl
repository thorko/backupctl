#!/usr/bin/perl
use strict;
use warnings;
use Log::Log4perl;
use Getopt::Long;
use Config::Simple;
use IO::Socket;
use POSIX qw/strftime/;
use Fcntl qw(:flock);

my $help = 0;
my $debug = 0;
my $verbose = 0;
my $status = 0;
my %cfg;
my $config = "";
my $date = strftime("%Y%m%d", localtime);

Getopt::Long::Configure('bundling');
GetOptions(
	"c|config=s" => \$config,
	"v|verbose" => \$verbose,
	"d|debug" => \$debug,
	"h|help" => \$help,
);

if ( $help || $config eq "" ) {
	&help_msg;
	exit 0;
}


Config::Simple->import_from($config, \%cfg);

$cfg{'log.loglevel'} = "DEBUG" if ($debug);
my $log_conf;
if ( $verbose ) {
$log_conf = "
	log4perl.rootLogger=$cfg{'log.loglevel'}, screen, Logfile
	log4perl.appender.screen = Log::Log4perl::Appender::Screen
	log4perl.appender.screen.stderr = 0
	log4perl.appender.screen.layout = PatternLayout
	log4perl.appender.screen.layout.ConversionPattern = %d %p> %F{1}:%L %M - %m%n

	log4perl.appender.Logfile=Log::Log4perl::Appender::File
  	log4perl.appender.Logfile.filename=$cfg{'log.logfile'}
	log4perl.appender.Logfile.mode=append
	log4perl.appender.Logfile.layout=PatternLayout
	log4perl.appender.Logfile.layout.ConversionPattern=%d %-5p %c - %m%n
";
} else {
	$log_conf = "log4perl.rootLogger=$cfg{'log.loglevel'}, Logfile
	log4perl.appender.Logfile=Log::Log4perl::Appender::File
  	log4perl.appender.Logfile.filename=$cfg{'log.logfile'}
	log4perl.appender.Logfile.mode=append
	log4perl.appender.Logfile.layout=PatternLayout
	log4perl.appender.Logfile.layout.ConversionPattern=%d %-5p %c - %m%n
";
}

Log::Log4perl->init(\$log_conf);
our $log = Log::Log4perl->get_logger();

if ( -f $cfg{'backup_settings.lock'} ) {
	#if ( ! flock(DATA, LOCK_EX|LOCK_NB) ) { 
	$log->error("Program already running."); 
	exit 1; 
} else {
	system("/usr/bin/touch $cfg{'backup_settings.lock'}");
}

$log->debug("Trying to ping $cfg{'backup_settings.host'} on port $cfg{'backup_settings.port'}");
my $remote = IO::Socket::INET->new(
    Proto    => "tcp",
    PeerAddr => $cfg{'backup_settings.host'},
    PeerPort => $cfg{'backup_settings.port'},
    Timeout  => 8,
);

if(!$remote) {
  $log->error("couldn't ping $cfg{'backup_settings.host'}");
  unlink($cfg{'backup_settings.lock'});
  exit 1;
}
$log->debug("got ping...");

# check files
foreach my $f ( $cfg{'backup_settings.key'},
		$cfg{'backup_settings.source_file'},
		$cfg{'backup_settings.exclude_file'} ) {
	&check_file($f);
}

my $user = $cfg{'backup_settings.user'};
my $key = $cfg{'backup_settings.key'};
my $port = $cfg{'backup_settings.port'};
my $host = $cfg{'backup_settings.host'};
my $dest = $cfg{'backup_settings.destination_folder'};
my $keep_days = $cfg{'backup_settings.keep_days'};

my $ssh = "ssh -i $key -o StrictHostKeyChecking=no -p $port $user\@$host";
my $cmd = "$ssh \"if [ ! -d $dest/backup.$date ]; then /bin/cp -al $dest/\\\$(ls -1 $dest | tail -1) $dest/backup.$date; fi\"";
$log->debug("$cmd");
my $out = qx{$cmd};
$log->debug("output: $out");

$cmd = "$ssh \"folders=\\\$(find $dest -maxdepth 1 -type d -name \\\"backup*\\\" | wc -l); if [ \\\$folders -gt $keep_days ]; then diff=\\\$((\\\$folders - $keep_days)); echo \\\"will remove \\\$diff directories\\\" >> /tmp/backup.log; find $dest -maxdepth 1 -type d -name \\\"backup*\\\" | sort -r | tail -n \\\$diff | xargs rm -rf; fi\"";
$log->debug("$cmd");
$out = qx{$cmd};
$log->debug("output: $out");

$log->debug("$ssh \"test -d $dest/backup.$date || echo \"1\"\"");
$out = qx{$ssh "test -d $dest/backup.$date || echo '1'"};

if ( $out =~ /1/ ) {
	$log->error("Stopping backup, cause destination folder does not exist");
	unlink($cfg{'backup_settings.lock'});
	exit 1;
}
sleep 5;
$log->info("running rsync...");
print("/usr/bin/rsync -$cfg{'backup_settings.rsync_options'} -e \"ssh -i $cfg{'backup_settings.key'} \\
-p $cfg{'backup_settings.port'}\" --log-file=$cfg{'log.logfile'} \\
--exclude-from=$cfg{'backup_settings.exclude_file'} \\
--files-from=$cfg{'backup_settings.source_file'} / $cfg{'backup_settings.user'}\@$cfg{'backup_settings.host'}:$cfg{'backup_settings.destination_folder'}/backup.$date/") if ($debug);
system("/usr/bin/rsync -$cfg{'backup_settings.rsync_options'} -e \"ssh -i $cfg{'backup_settings.key'} -p $cfg{'backup_settings.port'}\" --log-file=$cfg{'log.logfile'} --exclude-from=$cfg{'backup_settings.exclude_file'} --files-from=$cfg{'backup_settings.source_file'} / $cfg{'backup_settings.user'}\@$cfg{'backup_settings.host'}:$cfg{'backup_settings.destination_folder'}/backup.$date/");

## cleanup lock
unlink($cfg{'backup_settings.lock'});

sub check_file {
	my $file = shift;
	if ( ! -e $file ) {
		$log->error("File: $file does not exist");
  		unlink($cfg{'backup_settings.lock'});
		exit 1;
	}
}

sub help_msg {
	print <<'MSG';
backupctl.pl -c <config file> [-v] [-d] [-h]

-c, --config	config file to use
-v, --verbose	be verbose
-d, --debug	debugging enabled
-h, --help	this help message


MSG
}

