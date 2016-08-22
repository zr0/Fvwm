#!/usr/bin/perl
#
# FvwmVolumeDisplay.pl
#
# A FvwmPerl module for changing & displaying audio volume on a laptop.
#
# Copyright Robert Geer bgeer@xmission.com
# Free software, no guarantee nor warrantee
#
# Uses ALSA amixer to control volume.
# Originally written for
#   FVWM 2.6.5 
#   Perl 5.16.1
#   ALSA driver 1.0.25; ALSA lib & utils 1.0.26
#
# To implement volume control via hotkeys (assuming X maps your
# hotkeys), add the following to your .fvwmrc:
#
# Module /[full path to]/FvwmVolumeDisplay.pl
# Key XF86AudioRaiseVolume  A N SendToModule /[full path to]/FvwmVolumeDisplay.pl volume_up
# Key XF86AudioLowerVolume  A N SendToModule /[full path to]/FvwmVolumeDisplay.pl volume_down
# Key XF86AudioMute         A N SendToModule /[full path to]/FvwmVolumeDisplay.pl mute
#
# The following menu fragment provides a non-hotkey mechanism for
# controlling FvwmVolumeDisplay.pl
#
# DestroyMenu "VolumeDisplay"
# AddToMenu "VolumeDisplay" "VolumeDisplay"
# +  "Start"         Module       /[full path to]/FvwmVolumeDisplay.pl
# +  "Volume Up"     SendToModule /[full path to]/FvwmVolumeDisplay.pl volume_up
# +  "Volume Down"   SendToModule /[full path to]/FvwmVolumeDisplay.pl volume_down
# +  "Volume Mute"   SendToModule /[full path to]/FvwmVolumeDisplay.pl mute
# +  "Refresh"       SendToModule /[full path to]/FvwmVolumeDisplay.pl refresh
# +  "Stop"          SendToModule /[full path to]/FvwmVolumeDisplay.pl stop
#
# Add the following to an existing menu to enable the fragment above:
#
# +  ""          Nop
# +  "VolumeDisplay" Popup "VolumeDisplay"
# +  ""          Nop
#
# This module assumes audio volume will be controlled by the master
# playback volume and master playback switch of sound card 0.  Use of
# a USB speaker plugged in during boot made my default sound card,
# named 'Realtek ALC861-VD', from number 0 to number 1 on my Toshiba
# A135-S4427.  I probably should make sound card number variable,
# maybe by command line argument or list all sound cards & do a search
# of some kind.  A future project...
#
# This module doesn't have a lot of error checking!
#

use lib `fvwm-perllib dir` ;
use FVWM::Module::Tk ;
use Tk ;               # preferably in this order
use Tk::ProgressBar ;

my $amixer = "/usr/bin/amixer" ;
my $master_playback_switch_numid = 0 ; 
my $master_playback_volume_numid = 0 ;
my $module ;
my $volume_progressbar ;
my $sound_card_number = 0 ;

# Make the window we will show:
my $mainwindow = MainWindow->new() ;

#______#
sub find_master_playback_volume_switch_numids

{
  # A text list, one control per line:
  my $amixer_control_glob = `$amixer -c $sound_card_number controls` ;

  # Find the Master Playback Volume line using
  # '^'  match beginning of line
  # '*'  any characters
  # 'Master Playback Volume'
  # '.+' any character except new line one or more times
  # '$'  to end of line
  # 'm'  treat input string as multiple lines:
  my ( $master_playback_volume_line ) =
      ( $amixer_control_glob =~ /(^.+Master Playback Volume.+$)/m ) ;

  # example: numid=14,iface=MIXER,name='Master Playback Volume'
  my @master_playback_volume_fields = split( ',',
                                             $master_playback_volume_line ) ;
  my $volume_numid_field = $master_playback_volume_fields[0] ;
  my @volume_numid_fields = split( '=',
                                   $volume_numid_field ) ;
  $master_playback_volume_numid = $volume_numid_fields[1] ;

  # print "$0:  \$master_playback_volume_numid: $master_playback_volume_numid\n" ;

  my ( $master_playback_switch_line ) =
      ( $amixer_control_glob =~ /(^.+Master Playback Switch.+$)/m ) ;

  # example: numid=15,iface=MIXER,name='Master Playback Switch'
  my @master_playback_switch_fields = split( ',',
                                             $master_playback_switch_line ) ;
  my $switch_numid_field = $master_playback_switch_fields[0] ;
  my @switch_numid_fields = split( '=',
                                   $switch_numid_field ) ;
  $master_playback_switch_numid = $switch_numid_fields[1] ;

  # print "$0:  \$master_playback_switch_numid: $master_playback_switch_numid\n" ;

} # find_master_playback_volume_switch_numids()

#______#
sub mute
{
  my @master_playback_switch_glob =
      split( /\n/,
             `$amixer cget name='Master Playback Volume'` ) ;
              # amixer from alsa_utils 1.0.27 failes using numid!
              # `$amixer cget numid=$master_playback_switch_numid` ) ;
  foreach $line (@master_playback_switch_glob)
  {
    # print "$0:  >$line<\n" ;
    if ($line =~ /: values/)
    {
      ( $label,
        $current_playback_switch ) = split( /=/,
                                            $line ) ;
      # print "$0:  " . $current_playback_switch . "\n" ;
      if ( $current_playback_switch eq "on" )
      {
        # Playback switch "on" means value is 1:
        return( 1 ) ;
      }
      else
      {
        # Playback switch "off" = "not on" means value is 0:
        return( 0 ) ;
      }
    }
  }

  # Default to playback switch "on" means value is 1:
  return( 1 ) ;

} # mute()

#______#
sub min_max_volume
{
  my @master_playback_volume_glob =
      split( /\n/,
             `$amixer cget name='Master Playback Volume'` ) ;
             # amixer from alsa_utils 1.0.27 failes using numid!
             # `$amixer cget numid=$master_playback_volume_numid` ) ;

  foreach $line (@master_playback_volume_glob)
  {
    # print "#0  >$line<\n" ;
    if ($line =~ /: values/)
    {
      ( $label,
        $current_playback_volume ) = split( /=/,
                                               $line ) ;
      # print "$0:  " . $current_playback_volume . "\n" ;
    }
    elsif ($line =~ /type=INTEGER/)
    {
      my ( $no_need1,
           $no_need2,
           $no_need3,
           $min_field,
           $max_field,
           @no_need4 ) = split( /,/,
                                $line ) ;
      ( my $min_label,
        $min ) = split( /=/,
                        $min_field ) ;
      ( my $max_label,
        $max ) = split( /=/,
                        $max_field ) ;
      # print "$0:  " . $min . " to " . $max . "\n" ;
    }
  }

  # print "\n" ;

  return( $min, $max, $current_playback_volume ) ;

} # min_max_volume()

my $scale_factor = 0 ;
my $scaled_volume = 0 ;

#______#
sub volume_mute
{
  my ( $mute ) = mute() ;

  if ($mute == 0)
  {
    # Switch currently off; turn it on:
    $mute = 1 ;
    # print "$0:  unmuting volume\n" ;
  }
  else
  {
    # Switch currently on; turn it off:
    $mute = 0 ;
    # print "$0:  muting volume\n" ;
  }

  `$amixer cset name='Master Playback Switch' $mute` ;
  # amixer from alsa_utils 1.0.27 failes using numid!
  `$amixer cset numid=$master_playback_switch_numid $mute` ;

  $mainwindow->update ;

} # volume_mute()

#______#
sub volume_up
{
  my ( $min,
       $max,
       $volume ) = min_max_volume() ;

  # print "$0:  " . $min . " < " . $volume . " < " . $max . "\n" ;
  
  if ($volume < $max)
  {
    ++$volume ;
  }
  # print "$0:  Setting volume to $volume\n" ;

  `$amixer cset name='Master Playback Volume' $volume` ;
  # amixer from alsa_utils 1.0.27 failes using numid!
  `$amixer cset numid=$master_playback_volume_numid $volume` ;

  $scaled_volume = ($volume - $min) * $scale_factor ;
  $mainwindow->update ;

} # volume_up()

#______#
sub volume_down
{
  my ( $min,
       $max,
       $volume ) = min_max_volume() ;

  # print "$0:  " . $min . " < " . $volume . " < " . $max . "\n" ;
  
  if ($min < $volume)
  {
    --$volume ;
  }

  # print "$0:  Setting volume to $volume\n" ;

  `$amixer cset name='Master Playback Volume' $volume` ;
  # amixer from alsa_utils 1.0.27 failes using numid!
  `$amixer cset numid=$master_playback_volume_numid $volume` ;

  $scaled_volume = ($volume - $min) * $scale_factor ;
  $mainwindow->update ;

} # volume_down()

# my $title = "Audio volume" ;

#______#
sub m_string_handler
{
  my ( $self,
       $event ) = @_ ;

  $command = $event->args->{text} ;

  if ($command =~ m/volume_up/)
  {
    volume_up() ;
  }
  elsif ($command =~ m/volume_down/)
  {
    volume_down() ;
  }
  elsif ($command =~ m/mute/)
  {
    volume_mute() ;
  }
  elsif ($command =~ m/refresh/)
  {
    $mainwindow->update ;
  }
  elsif ($command =~ m/stop/)
  {
    $mainwindow->destroy() ;
    exit( 0 ) ;
  }

} # m_string_handler()

#______#
sub create_module
{
  # Create the FVWM module:
  $module =
      new FVWM::Module::Tk( Name      => "FvwmVolumeDisplay.pl",
                            Mask      => M_STRING,
                            TopWindow => $mainwindow ) ;
#                           Debug     => 4 ) ;
  $module->add_default_error_handler ;
  
  # SendToModule commands arrive as M_STRING events.
  $module->add_handler( M_STRING,
                        \&m_string_handler ) ;

} # create_module()

#______#
sub create_window
{
  # Get this done!
  find_master_playback_volume_switch_numids() ;

  # Get current volume values:
  my ( $min,
       $max,
       $volume ) = min_max_volume() ;
  
  if ( (my $delta = ($max - $min)) != 0 )
  {
    $scale_factor = 100 / $delta ;
  }
  else
  {
    # print "$0:  Setting scale factor to default setting of 1!\n" ;
    $scale_factor = 1 ;
  }

  # Unknown to FVWM::Module::Tk
  $mainwindow->geometry( "+1-10" ) ;

  # # Try RoyalBlue4 or MidnightBlue for troughcolor:
  $volume_progressbar =
      $mainwindow->ProgressBar( -anchor      => 'w',
                                -blocks      => 10,
                                -colors      => [ 0,  'white' ],
                                -width       => 10,
                                -length      => 40,
                                -from        => 0,
                                -to          => 100,
                                -troughcolor => 'RoyalBlue4',
                                -variable    => \$scaled_volume ) ;
  $volume_progressbar->pack( -fill => 'x' ) ;

  $scaled_volume = ($volume - $min) * $scale_factor ;
  $mainwindow->update ;

  # print "$0:  Volume progressbar is created!\n" ;

  # Following useful for creating standalone program; requires mouse
  # cursor be in progressbar's window to work.
  # $mainwindow->bind( '<XF86AudioRaiseVolume>' => \&volume_up ) ;
  # $mainwindow->bind( '<XF86AudioLowerVolume>' => \&volume_down ) ;

} # create_window()

#______#
# main
{
  $amixer = `which /usr/bin/amixer` ;
  chomp( $amixer ) ;

  if ( -x $amixer )
  {
    print "$0:  Using $amixer to control audio.\n" ;
  }
  else
  {
    print "$0:  $amixer is not available...exiting.\n" ;
    exit( -1 ) ;
  }

  # $mainwindow is already created at top!
  create_module() ;

  create_window() ;

  # Known to Tk
  # MainLoop() ;

  # Unknown to Tk, known to FVWM::Module:
  $module->event_loop ;

} # main()

# End#!/usr/bin/perl
#
# FvwmVolumeDisplay.pl
#
# A FvwmPerl module for changing & displaying audio volume on a laptop.
#
# Copyright Robert Geer bgeer@xmission.com
# Free software, no guarantee nor warrantee
#
# Uses ALSA amixer to control volume.
# Originally written for
#   FVWM 2.6.5 
#   Perl 5.16.1
#   ALSA driver 1.0.25; ALSA lib & utils 1.0.26
#
# To implement volume control via hotkeys (assuming X maps your
# hotkeys), add the following to your .fvwmrc:
#
# Module /[full path to]/FvwmVolumeDisplay.pl
# Key XF86AudioRaiseVolume  A N SendToModule /[full path to]/FvwmVolumeDisplay.pl volume_up
# Key XF86AudioLowerVolume  A N SendToModule /[full path to]/FvwmVolumeDisplay.pl volume_down
# Key XF86AudioMute         A N SendToModule /[full path to]/FvwmVolumeDisplay.pl mute
#
# The following menu fragment provides a non-hotkey mechanism for
# controlling FvwmVolumeDisplay.pl
#
# DestroyMenu "VolumeDisplay"
# AddToMenu "VolumeDisplay" "VolumeDisplay"
# +  "Start"         Module       /[full path to]/FvwmVolumeDisplay.pl
# +  "Volume Up"     SendToModule /[full path to]/FvwmVolumeDisplay.pl volume_up
# +  "Volume Down"   SendToModule /[full path to]/FvwmVolumeDisplay.pl volume_down
# +  "Volume Mute"   SendToModule /[full path to]/FvwmVolumeDisplay.pl mute
# +  "Refresh"       SendToModule /[full path to]/FvwmVolumeDisplay.pl refresh
# +  "Stop"          SendToModule /[full path to]/FvwmVolumeDisplay.pl stop
#
# Add the following to an existing menu to enable the fragment above:
#
# +  ""          Nop
# +  "VolumeDisplay" Popup "VolumeDisplay"
# +  ""          Nop
#
# This module assumes audio volume will be controlled by the master
# playback volume and master playback switch of sound card 0.  Use of
# a USB speaker plugged in during boot made my default sound card,
# named 'Realtek ALC861-VD', from number 0 to number 1 on my Toshiba
# A135-S4427.  I probably should make sound card number variable,
# maybe by command line argument or list all sound cards & do a search
# of some kind.  A future project...
#
# This module doesn't have a lot of error checking!
#

use lib `fvwm-perllib dir` ;
use FVWM::Module::Tk ;
use Tk ;               # preferably in this order
use Tk::ProgressBar ;

my $amixer = "/usr/bin/amixer" ;
my $master_playback_switch_numid = 0 ; 
my $master_playback_volume_numid = 0 ;
my $module ;
my $volume_progressbar ;
my $sound_card_number = 0 ;

# Make the window we will show:
my $mainwindow = MainWindow->new() ;

#______#
sub find_master_playback_volume_switch_numids

{
  # A text list, one control per line:
  my $amixer_control_glob = `$amixer -c $sound_card_number controls` ;

  # Find the Master Playback Volume line using
  # '^'  match beginning of line
  # '*'  any characters
  # 'Master Playback Volume'
  # '.+' any character except new line one or more times
  # '$'  to end of line
  # 'm'  treat input string as multiple lines:
  my ( $master_playback_volume_line ) =
      ( $amixer_control_glob =~ /(^.+Master Playback Volume.+$)/m ) ;

  # example: numid=14,iface=MIXER,name='Master Playback Volume'
  my @master_playback_volume_fields = split( ',',
                                             $master_playback_volume_line ) ;
  my $volume_numid_field = $master_playback_volume_fields[0] ;
  my @volume_numid_fields = split( '=',
                                   $volume_numid_field ) ;
  $master_playback_volume_numid = $volume_numid_fields[1] ;

  # print "$0:  \$master_playback_volume_numid: $master_playback_volume_numid\n" ;

  my ( $master_playback_switch_line ) =
      ( $amixer_control_glob =~ /(^.+Master Playback Switch.+$)/m ) ;

  # example: numid=15,iface=MIXER,name='Master Playback Switch'
  my @master_playback_switch_fields = split( ',',
                                             $master_playback_switch_line ) ;
  my $switch_numid_field = $master_playback_switch_fields[0] ;
  my @switch_numid_fields = split( '=',
                                   $switch_numid_field ) ;
  $master_playback_switch_numid = $switch_numid_fields[1] ;

  # print "$0:  \$master_playback_switch_numid: $master_playback_switch_numid\n" ;

} # find_master_playback_volume_switch_numids()

#______#
sub mute
{
  my @master_playback_switch_glob =
      split( /\n/,
             `$amixer cget name='Master Playback Volume'` ) ;
              # amixer from alsa_utils 1.0.27 failes using numid!
              # `$amixer cget numid=$master_playback_switch_numid` ) ;
  foreach $line (@master_playback_switch_glob)
  {
    # print "$0:  >$line<\n" ;
    if ($line =~ /: values/)
    {
      ( $label,
        $current_playback_switch ) = split( /=/,
                                            $line ) ;
      # print "$0:  " . $current_playback_switch . "\n" ;
      if ( $current_playback_switch eq "on" )
      {
        # Playback switch "on" means value is 1:
        return( 1 ) ;
      }
      else
      {
        # Playback switch "off" = "not on" means value is 0:
        return( 0 ) ;
      }
    }
  }

  # Default to playback switch "on" means value is 1:
  return( 1 ) ;

} # mute()

#______#
sub min_max_volume
{
  my @master_playback_volume_glob =
      split( /\n/,
             `$amixer cget name='Master Playback Volume'` ) ;
             # amixer from alsa_utils 1.0.27 failes using numid!
             # `$amixer cget numid=$master_playback_volume_numid` ) ;

  foreach $line (@master_playback_volume_glob)
  {
    # print "#0  >$line<\n" ;
    if ($line =~ /: values/)
    {
      ( $label,
        $current_playback_volume ) = split( /=/,
                                               $line ) ;
      # print "$0:  " . $current_playback_volume . "\n" ;
    }
    elsif ($line =~ /type=INTEGER/)
    {
      my ( $no_need1,
           $no_need2,
           $no_need3,
           $min_field,
           $max_field,
           @no_need4 ) = split( /,/,
                                $line ) ;
      ( my $min_label,
        $min ) = split( /=/,
                        $min_field ) ;
      ( my $max_label,
        $max ) = split( /=/,
                        $max_field ) ;
      # print "$0:  " . $min . " to " . $max . "\n" ;
    }
  }

  # print "\n" ;

  return( $min, $max, $current_playback_volume ) ;

} # min_max_volume()

my $scale_factor = 0 ;
my $scaled_volume = 0 ;

#______#
sub volume_mute
{
  my ( $mute ) = mute() ;

  if ($mute == 0)
  {
    # Switch currently off; turn it on:
    $mute = 1 ;
    # print "$0:  unmuting volume\n" ;
  }
  else
  {
    # Switch currently on; turn it off:
    $mute = 0 ;
    # print "$0:  muting volume\n" ;
  }

  `$amixer cset name='Master Playback Switch' $mute` ;
  # amixer from alsa_utils 1.0.27 failes using numid!
  `$amixer cset numid=$master_playback_switch_numid $mute` ;

  $mainwindow->update ;

} # volume_mute()

#______#
sub volume_up
{
  my ( $min,
       $max,
       $volume ) = min_max_volume() ;

  # print "$0:  " . $min . " < " . $volume . " < " . $max . "\n" ;
  
  if ($volume < $max)
  {
    ++$volume ;
  }
  # print "$0:  Setting volume to $volume\n" ;

  `$amixer cset name='Master Playback Volume' $volume` ;
  # amixer from alsa_utils 1.0.27 failes using numid!
  `$amixer cset numid=$master_playback_volume_numid $volume` ;

  $scaled_volume = ($volume - $min) * $scale_factor ;
  $mainwindow->update ;

} # volume_up()

#______#
sub volume_down
{
  my ( $min,
       $max,
       $volume ) = min_max_volume() ;

  # print "$0:  " . $min . " < " . $volume . " < " . $max . "\n" ;
  
  if ($min < $volume)
  {
    --$volume ;
  }

  # print "$0:  Setting volume to $volume\n" ;

  `$amixer cset name='Master Playback Volume' $volume` ;
  # amixer from alsa_utils 1.0.27 failes using numid!
  `$amixer cset numid=$master_playback_volume_numid $volume` ;

  $scaled_volume = ($volume - $min) * $scale_factor ;
  $mainwindow->update ;

} # volume_down()

# my $title = "Audio volume" ;

#______#
sub m_string_handler
{
  my ( $self,
       $event ) = @_ ;

  $command = $event->args->{text} ;

  if ($command =~ m/volume_up/)
  {
    volume_up() ;
  }
  elsif ($command =~ m/volume_down/)
  {
    volume_down() ;
  }
  elsif ($command =~ m/mute/)
  {
    volume_mute() ;
  }
  elsif ($command =~ m/refresh/)
  {
    $mainwindow->update ;
  }
  elsif ($command =~ m/stop/)
  {
    $mainwindow->destroy() ;
    exit( 0 ) ;
  }

} # m_string_handler()

#______#
sub create_module
{
  # Create the FVWM module:
  $module =
      new FVWM::Module::Tk( Name      => "FvwmVolumeDisplay.pl",
                            Mask      => M_STRING,
                            TopWindow => $mainwindow ) ;
#                           Debug     => 4 ) ;
  $module->add_default_error_handler ;
  
  # SendToModule commands arrive as M_STRING events.
  $module->add_handler( M_STRING,
                        \&m_string_handler ) ;

} # create_module()

#______#
sub create_window
{
  # Get this done!
  find_master_playback_volume_switch_numids() ;

  # Get current volume values:
  my ( $min,
       $max,
       $volume ) = min_max_volume() ;
  
  if ( (my $delta = ($max - $min)) != 0 )
  {
    $scale_factor = 100 / $delta ;
  }
  else
  {
    # print "$0:  Setting scale factor to default setting of 1!\n" ;
    $scale_factor = 1 ;
  }

  # Unknown to FVWM::Module::Tk
  $mainwindow->geometry( "+1-10" ) ;

  # # Try RoyalBlue4 or MidnightBlue for troughcolor:
  $volume_progressbar =
      $mainwindow->ProgressBar( -anchor      => 'w',
                                -blocks      => 10,
                                -colors      => [ 0,  'white' ],
                                -width       => 10,
                                -length      => 40,
                                -from        => 0,
                                -to          => 100,
                                -troughcolor => 'RoyalBlue4',
                                -variable    => \$scaled_volume ) ;
  $volume_progressbar->pack( -fill => 'x' ) ;

  $scaled_volume = ($volume - $min) * $scale_factor ;
  $mainwindow->update ;

  # print "$0:  Volume progressbar is created!\n" ;

  # Following useful for creating standalone program; requires mouse
  # cursor be in progressbar's window to work.
  # $mainwindow->bind( '<XF86AudioRaiseVolume>' => \&volume_up ) ;
  # $mainwindow->bind( '<XF86AudioLowerVolume>' => \&volume_down ) ;

} # create_window()

#______#
# main
{
  $amixer = `which /usr/bin/amixer` ;
  chomp( $amixer ) ;

  if ( -x $amixer )
  {
    print "$0:  Using $amixer to control audio.\n" ;
  }
  else
  {
    print "$0:  $amixer is not available...exiting.\n" ;
    exit( -1 ) ;
  }

  # $mainwindow is already created at top!
  create_module() ;

  create_window() ;

  # Known to Tk
  # MainLoop() ;

  # Unknown to Tk, known to FVWM::Module:
  $module->event_loop ;

} # main()

# End
