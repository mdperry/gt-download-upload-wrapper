package GNOS::Download;

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
    MILLISECONDS_IN_AN_HOUR => 3600000,
};

#############################################################################################
# DESCRIPTION                                                                               #
#############################################################################################
#  This module is wraps the gtdownload script and retries the downloads if it freezes up.   #
#############################################################################################
# USAGE: run_uplaod($command, $file, $retries);                                             #
#        Where the command is the full gtdownlaod command                                   #
#############################################################################################

my $md5_sleep= 240;
my $cooldown = 60;

sub run_download {
    my ($class, $command, $file, $retries) = @_;

    $retries //= 30;

    my $thr = threads->create(\&launch_and_monitor, $command);

    my $count = 0;
    while( not (-e $file) ) {
        sleep $cooldown;

        if ( not $thr->is_running()) { 
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

    say "Total number of tries: $count";
    say 'DONE';
    $thr->join() if ($thr->is_running());
    
    return 1;
}

sub launch_and_monitor {
    my ($command) = @_;

    my $my_object = threads->self;
    my $my_tid = $my_object->tid;

    local $SIG{KILL} = sub { say "GOT KILL FOR THREAD: $my_tid";
                             threads->exit;
                           };

    my $pid = open my $in, '-|', "$command 2>&1";

    my $time_last_downloading = 0;
    my $last_reported_size = 0;
    while(<$in>) { 
        my ($size, $percent, $rate) = $_ =~ m/^Status:\s*(\d+.\d+|\d+|\s*)\s*[M|G]B\s*downloaded\s*\((\d+.\d+|\d+|\s)%\s*complete\)\s*current rate:\s+(\d+.\d+|\d+| )\s+MB\/s/g;

        if ($size > $last_reported_size) {
            $time_last_downloading = time;
        }
        elsif (($time_last_downloading != 0) and ( (time - $time_last_downloading) > MILLISECONDS_IN_AN_HOUR) ) {
            say 'Killing Thread - Timed out '.time;
            exit;
        }
        $last_reported_size = $size;
    }
}

1;
