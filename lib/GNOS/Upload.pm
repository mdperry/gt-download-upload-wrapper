package GNOS::Upload;

use warnings;
use strict;

use feature qw(say);
use autodie;
use Carp qw( croak );

use Config;
$Config{useithreads} or croak('Recompile Perl with threads to run this program.');
use threads 'exit' => 'threads_only';
use Storable 'dclone';

use constant {
   MILLISECONDS_IN_AN_HOUR => 3600000
};

my $cooldown = 60;
my $md5_sleep = 240;

#############################################################################################
# DESCRIPTION                                                                               #
#############################################################################################
#  This module is wraps the gtupload script and retries the downloads if it freezes up.     #
#############################################################################################
# USAGE: run_upload($command, $metadata_file, $retries);                                    #
#        Where $command is the full gtupload command                                        #
#############################################################################################

sub run_upload {
    my ($class, $command, $metadata_file, $retries) = @_;

    $retries //=30;
    say "CMD: $command";

    my $thr = threads->create(\&launch_and_monitor, $command);
    my $count = 0;

    while((not -e $metadata_file) or (not `cat $metadata_file` =~ /OK/)) {
        sleep $cooldown;
        if (not $thr->is_running()) {
            if (++$count < $retries ) {
                say 'KILLING THE THREAD!!';
                # kill and wait to exit
                $thr->kill('KILL')->join();
                $thr = threads->create(\&launch_and_monitor, $command);
                sleep $md5_sleep;
            }
            else {
                say "Surpassed the number of retries: $retries";
                exit 1;
            }
        }
    }

    say "Total number of attempts: $count";
    say 'DONE';
    $thr->join() if ($thr->is_running());
 
    return;
}

sub launch_and_monitor {
    my ($command) = @_;

    my $my_object = threads->self;
    my $my_tid = $my_object->tid;

    local $SIG{KILL} = sub { say "GOT KILL FOR THREAD: $my_tid";
                             threads->exit;
                           };
    # system doesn't work, can't kill it but the open below does allow the sub-process to be killed
    #system($cmd);
    my $pid = open my $in, '-|', "$command 2>&1";
    
    my $time_last_uploading = time;
    my $last_reported_uploaded = 0;
    while(<$in>) {
        my ($uploaded, $percent, $rate) = $_ =~ m/^Status:\s+(\d+.\d+|\d+| )\s+[M|G]B\suploaded\s*\((\d+.\d+|\d+| )%\s*complete\)\s*current\s*rate:\s*(\d+.\d+|\d+| )\s*[M|k]B\/s/g;
        if ($uploaded > $last_reported_uploaded) {
            $time_last_uploading = time;
        }
        elsif ( (time - $time_last_uploading) > MILLISECONDS_IN_AN_HOUR) {
            say 'Killing Thread - Timed Out';
            exit;
        }
        $last_reported_uploaded = $uploaded;
    }
}

1;