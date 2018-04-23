#!/usr/bin/perl

use Modern::Perl;
use lib 'lib';

use Net::FTP;
use URI::Escape;
use POSIX qw(strftime);
use MARC::Batch;
use File::Spec::Functions;
use File::Basename;
use Log::Log4perl;
use Log::Log4perl::MDC;
use Getopt::Long;
use Config::Tiny;
use utf8;

my $script_dir = dirname(__FILE__);
my $script_name = $0;
my $config = Config::Tiny->read('gobi.pl.conf', 'utf8');

Log::Log4perl::init($config->{_}->{log4perl_config} || 'log4perl.conf');
my $logger = Log::Log4perl->get_logger('Gobi.fetchgobi');

$config = $config->{fetchgobi};

my ($file_date, $local_directory);
GetOptions(
    'file-date=s' => \$file_date,
    'local-directory=s' => \$local_directory,
);

die('--file-date required') unless $file_date;
die('--local-directory required') unless $local_directory;

my $retry_dir = catfile($script_dir, 'fetchgobi_retry');

$logger->info("$script_name started");

opendir(D, $retry_dir) or $logger->logdie("Can't open directory: $!");
my @file_dates_retry = grep(/^\d{6}$/, readdir(D));
closedir(D);

$logger->warn(
    "Found file dates that will be attempted again: ",
    join(', ', @file_dates_retry)
) if @file_dates_retry;

# Start poor man's transfer-transaction
{
    my $retry_file = catfile($retry_dir, $file_date);
    my $status = system("touch $retry_file");
    $logger->logdie("Unable to touch $retry_file") if $status;
}

# Start FTP: connect and login
my $ftp = Net::FTP->new($config->{ftp_host})
    or $logger->logdie("FTP: Can't connect: $@");

$ftp->login($config->{ftp_username}, $config->{ftp_password})
    or $logger->logdie("FTP: Can't login");

# Change directory
$ftp->cwd($config->{ftp_remote_dir})
    or $logger->logdie("FTP: Can't change dir to " . $config->{ftp_remote_dir});

# Get a listing of files
my @files = $ftp->ls()
    or $logger->logdie("No files available on remote server: " . $config->{ftp_host});

$logger->logdie("No files on remote server: " . $config->{ftp_host}) unless (@files);

# Specify a binary tranfer
$ftp->binary() or $logger->logdie("FTP: Can't specify binary type");

my @file_dates = (@file_dates_retry, $file_date);

my $file_prefixes_p = join('|', split(/\s*,\s*/, $config->{marc_file_prefixes}));
my %file_date_regexps = map { $_ => qr/^(?:$file_prefixes_p)$_\.mrc$/ } @file_dates;

FILE_DATE: foreach my $_file_date (keys %file_date_regexps) {
    foreach my $marc_file (grep { $_ =~ $file_date_regexps{$_file_date} } @files) {
        if ($ftp->get($marc_file, catfile($local_directory, $marc_file))) {
            $logger->info("Downloaded: $marc_file");
        }
        else {
            # @TODO: How to get error message from ftp?
            $logger->error("FTP: Problem downloading $marc_file from " . $config->{ftp_host});
            next FILE_DATE;
        }
    }
    my $retry_file = catfile($retry_dir, $_file_date);
    # Complete poor man's transfer transaction
    unlink $retry_file or $logger->logdie("Unable to remove $retry_file: $!");
}
$ftp->quit();
$logger->info("$script_name finished");
