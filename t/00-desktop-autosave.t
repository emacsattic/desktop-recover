# Test file created outside of h2xs framework.
# Run this like so: `perl 00-desktop-autosave.t'
#   doom@kzsu.stanford.edu     2009/03/29 19:22:34

use Test::More;
BEGIN { plan tests => 3 };

use warnings;
use strict;
$|=1;
use Data::Dumper;
use Carp;
use Cwd qw( cwd abs_path );
use File::Path qw(mkpath);
use File::Basename qw( fileparse basename dirname );
use File::Copy     qw( copy move );
use Fatal          qw( open close mkpath copy move );
use Emacs::Run;

# Note: change the alternative to 0 before shipping
my $DEBUG   = $ENV{ TEST_EMACS_DEBUG }   || 0;
# Note: with $VERBOSE emacs stderr messages included in output (may break tests)
my $VERBOSE = $ENV{ TEST_EMACS_VERBOSE } || 0;
($DEBUG) && print STDERR "\nRunning $0...\n";

ok(1, "If we made it this far, we're ok. All modules are loaded.");

use FindBin qw( $Bin );  # ~/End/Cave/DesktopAutosave/lib/emacs/t/

my $test_config_pl = "$Bin/etc/config.pl";
my $elisp_lib   = "$Bin/..";   # location of *.el being tested
my $elisp_t_lib = "$Bin/lib";  # misc elisp just for tests
my $tmp_dir     = "$Bin/tmp";
mkpath( $tmp_dir ) unless( -d $tmp_dir );

my $archive_loc = "$Bin/dat/00-archive";

my $emacs     = $ENV{ TEST_EMACS_BINARY } || 'emacs';
my $dot_emacs = $ENV{ TEST_EMACS_INIT }   || '';

($DEBUG) && print STDERR "\n==>emacs: $emacs emacs init: $dot_emacs<==\n\n";

my $desktop_recover_autosave = "$elisp_lib/desktop-recover-autosave.el";
unless (-e $desktop_recover_autosave) {
  croak "Can not find package: $desktop_recover_autosave\n";
}

my @nameos = qw( wuhn tew thuree foah );

my @content_file = (
   "$archive_loc/content-00.txt",
   "$archive_loc/content-01.txt",
   "$archive_loc/content-02.txt",
   "$archive_loc/content-03.txt",
  );

# clear the decks for another run (teardown = first stage of setup)
chdir( $tmp_dir );
unlink( ".emacs.desktop" );
unlink( ".emacs.desktop.lock" );

{
  my $test_name = "Testing desktop-recover-save via Emacs::Run";
  # side-effects:
  #   also creates: files "wuhn", "tew", "thuree" and "foah"

  my $desktop_setup = "$elisp_t_lib/desktop-recover-setup.el";
  ($DEBUG) && print STDERR "\ndesktop_setup:$desktop_setup\n\n";

  my $elibs = [ $desktop_setup,
                $desktop_recover_autosave,
              ];

  unshift @{ $elibs }, $dot_emacs if $dot_emacs;

  my $er = Emacs::Run->new({
                            load_no_inits => 1,
                            emacs_path => $emacs,
                            emacs_libs => $elibs,
                            redirector => 'stdout_only'
                           });

  my $emacs_version = $er->emacs_version;
  if ($VERBOSE) {
    $er->set_redirector("all_output");
  }
  if ($DEBUG) {
    $er->debugging('1');
    print STDERR $emacs_version, "\n";
  }

  my @new_file = map{ "$tmp_dir/$_" } sort @nameos;

  foreach my $full_file (@new_file) {
    unlink( "$full_file" );     # more teardown
  }

  my $elisp_0 = qq{
          (progn
            (find-file "$new_file[0]")
            (insert-file-contents "$content_file[0]")
            (save-buffer)
            (find-file "$new_file[1]")
            (insert-file-contents "$content_file[1]")
            (save-buffer)
            (find-file "$new_file[2]")
            (insert-file-contents "$content_file[2]")
            (save-buffer)
            (find-file "$new_file[3]")
            (insert-file-contents "$content_file[3]")
            (save-buffer)
            (setq desktop-dirname "$tmp_dir") ;; critical for reliable test
            (desktop-recover-autosave-save)
            (desktop-recover-autosave-print-ordinary-buffer-names)
           )
          };

  ($DEBUG) && print STDERR "elisp: $elisp_0\n";

  my $result =
    $er->eval_elisp( $elisp_0 );

  my @buffers = sort split qr{\n}, $result;
  ($DEBUG) && print STDERR Dumper( \@buffers ), "\n";

  my @expected = sort @nameos;

#   is_deeply( \@buffers, \@expected,
#              "$test_name, using $emacs_version with $dot_emacs");

  my $label = "$test_name, using $emacs_version";
  $label .= " with $dot_emacs" if $dot_emacs;

  ok( is_sub_set_of( \@expected, \@buffers ), $label)
    or print STDERR "result: ". Dumper(\@buffers) . "\nExpected: " . Dumper(\@expected) . "\n" ;
}

# The following code
#  creates a new emacs window by forking off a child and then doing an exec
#  of the emacs command line -- it then tries to kill the emacs process
#  using the returned pid.  That doesn't quite work on this box:
#    Linux fineline 2.6.24-16-generic #1
#  but does on this one:
#    Linux dancer 2.6.27-9-generic #1
#  (I suspect a kernel bug that's already been fixed)
#  There's some additional hackery that tries to find the right pid to
#  kill if the expected pid doesn't seem to be the right one.

#  Since we're not using -batch, "print" and "message" do not go
#  to STDOUT or STDERR.

#  Instead we use a temporary file ("buffer.lst") to pass output.

#  Note: the fork/exec tricks use a blend of techniques from:
#   /home/doom/bin/child_to_parent_ipc_demo
#   /home/doom/End/Cave/GuiTest/bin/poc_emacs_launch_and_capture

{
  my $test_name = "Testing desktop-read (not using -batch)";
  chdir( $tmp_dir );

  # get a known desktop file from archive location
  unlink( ".emacs.desktop" );
  my $desktop_file = "$archive_loc/.emacs.desktop";
  copy( $desktop_file, $tmp_dir );

  # remove any lock so that desktop.el won't ask about it
  unlink( ".emacs.desktop.lock" );

  # create target files from archive (clean any existing copies first)
  foreach my $name (@nameos) {
    unlink( "$name" );
  }
  system( "tar xzf $archive_loc/files.tgz" );

  # Pass output from the new emacs through this file
  my $buffer_list_file = "$tmp_dir/buffer.lst";
  unlink( $buffer_list_file ) if -e $buffer_list_file;

  my $elisp =
    qq{
         (progn
           (desktop-read "$tmp_dir")
           (find-file "$buffer_list_file")
           (desktop-recover-autosave-insert-ordinary-buffer-names)
           (save-buffer)
         )
       };

  ($DEBUG) && print STDERR "elisp: $elisp\n";

  # if we weren't told which emacs to use, fall back on letting the
  # path sort it out.
  $emacs = 'emacs' unless( $emacs );

  if ($DEBUG) {
    $emacs .= ' --debug-init';
  }

  my $emacs_cmd;
  if ( not( $dot_emacs ) ) {
    $emacs_cmd = "$emacs -q -l $desktop_recover_autosave --eval '$elisp'";
  } else {
    $emacs_cmd =
      "$emacs -q -l $dot_emacs -l $desktop_recover_autosave --eval '$elisp'";
  }

  $emacs_cmd .= ' 2>/dev/null' unless ( $VERBOSE );

  ($DEBUG) && print STDERR "emacs_cmd: $emacs_cmd\n";

  if ( my $pid = fork ) {
    # this is parent code
    ($DEBUG) && print STDERR "I'm the parent, the child pid is $pid\n";

    #  kill the child emacs only after buffer.lst has been written
  LOOP: while(1) { # TODO loop needs to time out (what if *nothing* is written?)
      my $cutoff = 0;      # increase, if this seems flaky (TODO)
      if ( (-e $buffer_list_file) && ( (-s $buffer_list_file) > $cutoff ) ) {
        sleep 1; # a little time for things to settle down (paranoia)
        my $status =
          kill 1, $pid; # TODO  9 any better than 1? (the only way to be sure)
        ($DEBUG) && print STDERR "Bang, you're dead, pid $pid! Right?\n";

        if ( $status == 1 ) {   # must try harder
          my $realpid = find_real_emacs_pid( $pid );
          ($DEBUG) &&
            print STDERR "But status is $status, so instead we'll kill pid $realpid\n";
          kill 1, $realpid;
        }
        last LOOP;
      }
    }

  } else {
    # this is child code
    die "cannot fork: $!" unless defined $pid;

    ($DEBUG) && print STDERR "This is the child, about to exec:\n";
    ($DEBUG) && print STDERR "emacs_cmd: $emacs_cmd\n";
    exec( $emacs_cmd ); # replaces child with a new emacs: no change in pid
  }

  my @result;
  open my $fh, '<', $buffer_list_file or die "$!";
  while ( my $buffer_name = <$fh> ) {
    chomp( $buffer_name );
    push @result, $buffer_name;
    ($DEBUG) && print STDERR "buffer name: $buffer_name\n";
  }

  my @result_sorted = map{ s{\r$}{}xms; $_ } sort @result;

  my @expected = sort qw( wuhn tew thuree foah buffer.lst);
  # Note: this system uses "buffer.lst" to pass the output

#   is_deeply( \@result_sorted, \@expected,
#              "$test_name, using $emacs with $dot_emacs");

  my $label = "$test_name, using $emacs";
  $label .= " with $dot_emacs" if $dot_emacs;

  ok( is_sub_set_of( \@expected, \@result_sorted), $label)
    or print STDERR "result: ".
                    Dumper(\@result_sorted) .
                    "\nExpected: " .
                    Dumper(\@expected) . "\n" ;
}

# looks for an emacs child process invoking 'desktop-autosave.el' on
# the command-line that has a pid exactly one more than the given pid.
sub find_real_emacs_pid {
  my $child_pid = shift;
  my $emacs_cmd_marker = shift || basename( $desktop_recover_autosave );
  my $subname = ( caller(0) )[3];
  print STDERR "$subname called...\n";

  my $cmd = "ps ax --width 2000 | egrep emacs | egrep $emacs_cmd_marker";
  chomp(
    my @lines = qx{ $cmd }
  );

  my $pid_pat = qr{  ^
                     \s*
                     (\d+?)
                     \s
                   }xms;

  my ($candidate_pid, $real_pid);
  foreach my $line (@lines) {
    if( $line =~ m{ $pid_pat }xms ) {
      $candidate_pid = $1;
      if ( $candidate_pid == ($child_pid + 1) ) {
        $real_pid = $candidate_pid;
        return $real_pid;
      }
    }
  }
  return;
}


# return true if aref1 is a subset of aref2
sub is_sub_set_of {
  my $aref1 = shift;
  my $aref2 = shift;

  my %temp;
  $temp{ $_ } = 1 for @{ $aref2 };

  my $flag = 1;
  foreach my $item ( @{ $aref1 } ) {
    $flag &&= delete $temp{ $item };
  }
  return $flag;
}




# TODO what if you run without X available?  *Probably* doesn't work, but not
# sure.

