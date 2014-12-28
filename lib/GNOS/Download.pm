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
# USAGE: run_upload($command, $file, $retries, $cooldown_min, $timeout_min);                #
#        Where the command is the full gtdownlaod command                                   #
#############################################################################################

sub run_download {
    my ($class, $command, $file, $retries, $cooldown_min, $timeout_min) = @_;

    $retries //= 30;
    $timeout_min //= 60;
    $cooldown_min //= 1;

    my $timeout_mili = ($timeout_min / 60) * MILLISECONDS_IN_AN_HOUR;

    my $thr = threads->create(\&launch_and_monitor, $command);

    my $count = 0;
    while( not (-e $file) ) {

        if ( not $thr->is_running()) {
            if (++$count < $retries ) {
                say 'KILLING THE THREAD!!';
                # kill and wait to exit
                $thr->kill('KILL')->join();
                $thr = threads->create(\&launch_and_monitor, $command, $timeout_mili);
            }
            else {
               say "Surpassed the number of retries: $retries";
               exit 1;
            }
        }

        sleep $cooldown_min;
    }

    say "Total number of tries: $count";
    say 'DONE';
    $thr->join() if ($thr->is_running());

    return 1;
}

sub launch_and_monitor {
    my ($command, $timeout) = @_;

    my $my_object = threads->self;
    my $my_tid = $my_object->tid;

    local $SIG{KILL} = sub { say "GOT KILL FOR THREAD: $my_tid";
                             threads->exit;
                           };

    my $pid = open my $in, '-|', "$command 2>&1";

    my $time_last_downloading = 0;
    my $last_reported_size = 0;
    while(<$in>) {

        # just print the output for debugging reasons
        print "$_";

        # these will be defined if the program is actively downloading
	my ($size, $percent, $rate);
	$size = 0;
	$percent = 0;
	$rate = 0;
        my ($size, $percent, $rate) = $_ =~ m/^Status:\s*(\d+.\d+|\d+|\s*)\s*[M|G]B\s*downloaded\s*\((\d+.\d+|\d+|\s)%\s*complete\)\s*current rate:\s+(\d+.\d+|\d+| )\s+MB\/s/g;

        # test to see if the thread is md5sum'ing after an earlier failure
        # this actually doesn't produce new lines, it's all on one line but you
        # need to check since the md5sum can take hours and this would cause a timeout
        # and a kill when the next download line appears since it could be well past
        # the timeout limit
        my $md5sum = 0;
        if ($_ =~ m/^Download resumed, validating checksums for existing data/g) { $md5sum = 1; } else { $md5sum = 0; }

        if ((defined($size) && $size > $last_reported_size) || $md5sum) {
            $time_last_downloading = time;
        }
        elsif (($time_last_downloading != 0) and ( (time - $time_last_downloading) > $timeout) ) {
            say 'Killing Thread - Timed out '.time;
            exit;
        }
        $last_reported_size = $size;
    }
}

1;
