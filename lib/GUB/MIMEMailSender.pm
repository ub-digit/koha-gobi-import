package GUB::MIMEMailSender;

use Modern::Perl;

our $VERSION = '0.1';

# use Log::Dispatch::Types;

# use Specio;
# use Specio::Declare;
# use Specio::Library::Builtins;

use Email::MIME;
use Email::Simple;
use Email::Sender::Simple;
# use Email::Simple::Creator; # ??? Testa ta bort denna, kanske ej behovs
use Email::Sender::Transport::SMTP;
use File::Basename;
use IO::All;

use Log::Log4perl::MDC; # Need use?

# use Try::Tiny;

use Params::ValidationCompiler qw( validation_for );

# @TODO: use parent?

use base qw( Log::Dispatch::Email );

{
    my $validator_params = {
        smtp_host => { default => 'localhost' },
        smtp_port => { default => 25 },
        reply_to => 0,
        cc => 0,
    };
    my $validator = validation_for(
        params => $validator_params,
        slurpy => 1,
    );

    sub new {
        my $class = shift;
        my %p = $validator->(@_);

        my %params = map { $_ => delete $p{$_} } keys %{$validator_params};
        my $self = $class->SUPER::new(%p);
        foreach my $key (keys %params) {
            $self->{$key} = $params{$key};
        }

        return $self;
    }
}

sub send_email {
    my $self = shift;
    my %p = @_;

    my $header = [
        'To' => ( join ',', @{$self->{to}} ),
        'From' => $self->{from} || 'GUBMailSender@ub.gu.se',
    ];

    push @{$header}, 'Subject' => $self->{subject} if $self->{subject};
    push @{$header}, 'Reply-To' => $self->{reply_to} if $self->{reply_to};
    push @{$header}, 'cc' => $self->{cc} if $self->{cc};

    # Quick and dirty, only support one attachment of type
    # text/plain
    # TODO: Would be quite easy to autodetect mime and support multiple files

    my $mail;
    my $attachment = Log::Log4perl::MDC->get('attachment');

    if ($attachment) {
        # TODO: Should have some more validation
        # that attachment is a path and file exists
        # plus we take this from the context thingy, not class param
        my ($filename) = fileparse($attachment);
        $mail = Email::MIME->create(
            header => $header, # header/header_str/header_raw, wtf?
            parts => [
                Email::MIME->create(
                    'body' => %p{message},
                ),
                Email::MIME->create(
                    attributes => {
                        filename => $filename,
                        content_type => 'text/plain',
                    },
                    body => io($attachment),
                    # body => io( "2004-financials.pdf" )->binary->all, # ????
                ),
            ]
        );
    }
    else {
        $mail = Email::Simple->create(
            header => $header,
            body => $p{message},
        );
    }

    # TODO: SMTP authentication params
    my $transport = Email::Sender::Transport::SMTP->new(
        {
            host => $self->{smtp_host},
            port => $self->{smtp_port},
        }
    );
    Email::Sender::Simple->try_to_send($mail, { transport => $transport });
}

1;
