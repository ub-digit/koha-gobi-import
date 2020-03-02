#!/usr/bin/perl

use Modern::Perl;
use utf8;

use File::Spec::Functions; # catfile
use File::Basename;
use lib dirname(__FILE__) . '/lib';

use MARC::Batch;
use MARC::Record;

use Log::Log4perl;
use Log::Log4perl::MDC;
use Getopt::Long;
use Config::Tiny;

my $script_dir = dirname(__FILE__);
my $config = Config::Tiny->read(catfile($script_dir, 'gobi.pl.conf'), 'utf8');

Log::Log4perl::init($config->{_}->{log4perl_config} || catfile($script_dir, 'log4perl.conf'));

my $logger = Log::Log4perl->get_logger('Gobi.adjustgobi');
my $mail_report_logger = Log::Log4perl->get_logger('Gobi.MailNotify');

$config = $config->{adjustgobi};

my ($input_file, $output_file);
GetOptions(
    'input-file=s' => \$input_file,
    'output-file=s' => \$output_file,
);

die("--input-file is required") unless ($input_file);
die("--output-file is required") unless ($output_file);

open(my $output_fh, ">", $output_file) or $logger->logdie("Could not open $output_file for write: $!");
open(my $input_fh, "<", $input_file) or $logger->logdie("Could not open $input_file: $!");
binmode $input_fh, ':raw';
binmode $output_fh, ':utf8';
my $batch;
eval { $batch = MARC::Batch->new('USMARC', $input_fh) };
$logger->logdie("Could not read marc from $input_file: $@") if $@;

my @records_formatted;

my $record_count = 0;
while (1) {
    $record_count++;
    # In eval?
    my $record;
    eval { $record = $batch->next() };
    if ($@) {
        $logger->logdie("Error decoding record $record_count in $input_file: $@");
    }
    elsif (!$record) {
        my @warnings = $batch->warnings();
        if (@warnings) {
            $logger->error("Error decoding record $record_count in $input_file with warnings: @warnings");
            next;
        }
        else {
            last;
        }
    }

    my $field;
    my @fields;

    ## update 008
    my $f008 = $record->field('008');
    my $data = $f008->data();
    substr($data, 23, 1) = 'o';
    # substr( $data,11,4 ) = '    ';
    substr($data, 39, 1) = 'c';
    $f008->update($data);
    ## look for a 041 field
    my $f041 = $record->field('041');
    ## if we don't have a field 041 add it
    if (!$f041) {
        my $lng = substr($data, 35, 3);
        $record->insert_fields_ordered(MARC::Field->new('041', ' ', ' ', a => $lng));
    }

    ## Delete fields
    foreach my $tag (
        '010',
        '015',
        '016',
        '019',
        '029',
        '037',
        '049',
        '055',
        '060',
        '070',
        '072',
        '080',
        '084',
        '090',
        '092',
        '096'
    ) {
        my @fields = $record->field($tag);
        if (@fields) {
            $record->delete_fields(@fields);
        }
    }

    ## Delete subfields z in 035
    my $field_035 = $record->field('035');
    if ($field_035) {
        my $field_035z = $record->subfield('035', 'z');
        if ($field_035z) {
            $field_035->delete_subfield(code => 'z');
        }
    }

    # add Gdig to 040
    my $field_040 = $record->field('040');
    if ($field_040) {
        $field_040->add_subfields('d' => 'Gdig');
    }

    # Elektronisk resurs
    my $f245 = $record->field('245');
    if ($f245) {
        my $sub_h = $f245->subfield('h');
        if ($sub_h) {
            $sub_h =~ s/electronic resource/Elektronisk resurs/g;
            $f245->update( h => $sub_h );
        }
    }

    # 6XX sub 2 noload
    my $noload_regexp = qr/fast|bisacsh|gnd|idszbz|gtt|ram|swd|stw|eclas|embn|embne|rero|larpc|idsbb|unbist|uole/;
    @fields = $record->field('6..');
    foreach my $field (@fields) {
        my $subfield_2 = $field->subfield('2');
        if ($subfield_2) {
            if ($subfield_2 =~ $noload_regexp && $field->indicator(2) == 7) {
                $record->delete_field($field);
            }
        }
        elsif ($field->indicator(2) == 3 || $field->indicator(2) == 5 || $field->indicator(2) == 6) {
            $record->delete_field($field);
        }
    }

    # Edit 776 subfields
    my @field_776 = $record->field('776');
    if (@field_776) { # start 776
        foreach my $field_776 ( @field_776 ) {
            my @sub_z = $field_776->subfield('z');
            foreach my $sub_z (@sub_z) {
                if ( $sub_z ) {
                    $sub_z =~ s/[^0-9X]*//g;
                }
            }
            my @sub_i = $field_776->subfield('i');
            foreach my $sub_i (@sub_i) {
                if ($sub_i =~ m/^Online|Electronic|ebook|Ebook/) {
                    $record->delete_field($field_776);
                }
            }
            my @sub_c = $field_776->subfield('c');
            foreach my $sub_c (@sub_c) {
                if ( $sub_c =~ m/^Online|Electronic/ ) {
                    $record->delete_field($field_776);
                }
            }
            my $title = $record->title_proper();
            if ($title) { # start title
                $title =~ s/\s(:|\/)$//g;
                my $year;
                my $author = $record->subfield('100','a');
                my $fixed = $record->field('008');
                $year = substr($fixed->as_string(), 7, 4);
                if ($author) {
                    $author =~ s/,$//g;
                    unless ($author =~ /[A-Z]\.$/) {
                        $author =~ s/\.$//g;
                    }
                    $field_776->update(i => 'Print:', a => $author, t => $title, d => $year);
                }
                else  {
                    $field_776->update(i => 'Print:', t => $title, d => $year);
                }

            } # end title
            # Reorder 776 subfields
            my @subfields = ();
            ## if we have a subfield i,a,t,d,z: add it.
            foreach my $subfield ('i', 'a', 't', 'd') {
                if (defined $field_776->subfield($subfield)) {
                    push @subfields, $subfield => $field_776->subfield($subfield);
                }
            }
            #       if (defined($field_776->subfield('z'))) {
            #         push(@subfields,'z',$field_776->subfield('z'));
            #     }
            foreach my $sub_z (@sub_z) {
                unless (length($sub_z) == 10) {
                    push @subfields, z => $sub_z;
                }
            }
            ## create a new 776 field using the new reordered subfields, replace old 776
            my $new = MARC::Field->new(
                '776',
                $field_776->indicator(1),
                $field_776->indicator(2),
                @subfields
            );
            $field_776->replace_with($new);
        }
    } # end 776

    # add ez to 856 u missing ez add zText and add lic info from 590 to 856 z
    my $zText = 'Tillgänglig för Göteborgs universitet / Online access for the University of Gothenburg';
    my $field_856 = $record->field('856');
    if ($field_856) {
        my $sub_u = $field_856->subfield('u');
        $field_856->add_subfields( 'z' => $zText );

        my $field_590 = $record->field('590');
        if ($field_590) {
            my $license = $field_590->as_string('a');
            $field_856->add_subfields('z' => "-- $license");
        }
    }

    # ok 20170905
    my @field_020 = $record->field('020');
    foreach my $field_020 ( @field_020 ) {
        my $isbn = $field_020->as_string();
        unless ( $isbn =~/^\d{13}/ ) {
            $record->delete_fields($field_020);
        }
    }
    push @records_formatted, "Record# $record_count:", $record->as_formatted(), "\n";

    # Write record
    $record->encoding('UTF-8'); # TODO: This is probably not needed
    print $output_fh $record->as_usmarc();
}
close($output_fh);
close($input_fh);

Log::Log4perl::MDC->put('attachment', $output_file);
Log::Log4perl::MDC->put('attachment-mime-type', 'application/marc');
$mail_report_logger->debug("\n" . join("\n", @records_formatted));
