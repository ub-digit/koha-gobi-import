#!/usr/bin/perl

use File::Spec::Functions; # catfile
use File::Basename;
use lib dirname(__FILE__) . '/lib';

use Modern::Perl;
use Log::Log4perl;
use Log::Log4perl::Level;
use Log::Log4perl::MDC;
use Getopt::Long;
use Config::Tiny;

# TODO: Could also support mail attachment?
my (
    $level,
    $message,
    $logger_ns,
    $attachment,
    $attachment_mime_type
);
GetOptions(
    'level=s' => \$level,
    'message=s' => \$message,
    'logger=s' => \$logger_ns,
    'attachment=s' => \$attachment,
    'attachment-mime-type=s' => \$attachment_mime_type,
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

my $script_dir = dirname(__FILE__);
my $config = Config::Tiny->read(catfile($script_dir, 'gobi.pl.conf'), 'utf8');
Log::Log4perl::init($config->{_}->{log4perl_config} || catfile($script_dir, 'log4perl.conf'));

my $logger = Log::Log4perl->get_logger($logger_ns);

if ($attachment) {
    Log::Log4perl::MDC->put('attachment', $attachment);
    if ($attachment_mime_type) {
        Log::Log4perl::MDC->put('attachment-mime-type', $attachment_mime_type);
    }
}

$logger->log($levels{$level}, $message);
