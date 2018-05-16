#!/usr/bin/perl

use Modern::Perl;

use File::Spec::Functions; # catfile
use File::Basename;
use lib dirname(__FILE__) . '/lib';

use Net::FTP;
use URI::Escape;
use POSIX qw(strftime);
use MARC::Batch;
use Log::Log4perl;
use Log::Log4perl::MDC;
use Getopt::Long;
use Config::Tiny;
use utf8;

my $script_dir = dirname(__FILE__);
my $script_name = $0;
my $config = Config::Tiny->read(catfile($script_dir, 'gobi.pl.conf'), 'utf8');

Log::Log4perl::init($config->{_}->{log4perl_config} || catfile($script_dir, 'log4perl.conf'));
my $logger = Log::Log4perl->get_logger('Gobi.fetchgobi');

$config = $config->{fetchgobi};

my (
    $file_date,
    $local_directory,
    $ftp_remote_dir,
    $file_pattern_string,
    $skip_files,
    $ftp_host,
    $ftp_username,
    $ftp_password,
);

GetOptions(
    'local-directory=s' => \$local_directory,
    'remote-directory=s' => \$ftp_remote_dir,
    'file-pattern=s' => \$file_pattern_string,
    'skip-files=s' => \$skip_files,
    'host=s' => \$ftp_host,
    'user=s' => \$ftp_username,
    'password=s' => \$ftp_password,
);

die('--local-directory required') unless $local_directory;
die('--host required') unless $ftp_host;
die('--user required') unless $ftp_username;
die('--password required') unless $ftp_password;

$file_pattern_string ||= '\.mrc$';
my %skip_files = map { $_ => undef } split(/\s*(?:,|\s+)\s*/, $skip_files);

$logger->info("$script_name started");

# Start FTP: connect and login
my $ftp = Net::FTP->new($ftp_host)
    or $logger->logdie("FTP: Can't connect: $@");

$ftp->login($ftp_username, $ftp_password)
    or $logger->logdie("FTP: Can't login");

# Change directory
$ftp->cwd($ftp_remote_dir)
    or $logger->logdie("FTP: Can't change dir to " . $ftp_remote_dir);

# Get a listing of files
my @files = $ftp->ls()
    or $logger->logdie("No files available on remote server: " . $ftp_host);

$logger->logdie("No files on remote server: " . $ftp_host) unless (@files);

# Specify a binary tranfer
$ftp->binary() or $logger->logdie("FTP: Can't specify binary type");

my $file_pattern = qr/$file_pattern_string/;

foreach my $marc_file (grep { $_ =~ $file_pattern && !(exists $skip_files{$_}) } @files) {
    if ($ftp->get($marc_file, catfile($local_directory, $marc_file))) {
        $logger->info("Downloaded: $marc_file");
    }
    else {
        # @TODO: How to get error message from ftp?
        $logger->error("FTP: Problem downloading $marc_file from " . $config->{ftp_host});
        next;
    }
}

$ftp->quit();
$logger->info("$script_name finished");
