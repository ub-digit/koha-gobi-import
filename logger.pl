#!/usr/bin/perl

use Modern::Perl;
use Log::Log4perl;
use Log::Log4perl::Level;
use Getopt::Long;
use Config::Tiny;
use lib 'lib';

# TODO: Could also support mail attachment?
my ($level, $message, $logger_ns);
GetOptions(
    'level=s' => \$level,
    'message=s' => \$message,
    'logger=s' => \$logger_ns,
);

die('--level required') unless $level;
die('--message required') unless $message;
die('--logger required') unless $logger_ns;

my %levels = (
    trace => $TRACE,
    debug => $DEBUG,
    info => $INFO,
    warn => $WARN,
    error => $ERROR,
    fatal => $FATAL,
);

die("invalid --level: $level") unless exists $levels{$level};

my $config = Config::Tiny->read('gobi.pl.conf', 'utf8');
Log::Log4perl::init($config->{_}->{log4perl_config} || 'log4perl.conf');

my $logger = Log::Log4perl->get_logger($logger_ns);
$logger->log($levels{$level}, $message);
