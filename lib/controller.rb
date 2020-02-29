#!/opt/local/bin/ruby -w
#!/usr/local/bin/ruby -w
#
# Command line controller for mlmp3p.rb 
# Version: 0.05
# Author: Alec Jacobson (alecjacobson@gmail.com)
#
#

# ruby from macports seems to work best on mac
# sudo port install ruby

# make sure this development folder is in load path
# this is needed for easy developement and debugging I don't think it is
# harmfully to distribute, but probably should remove or hid 
$LOAD_PATH << File.expand_path(File.dirname($0))

# standard package with Ruby, better than STDIN.gets for arrow keys etc.
# readline DOES NOT come with Apple's default ruby...better to get the real 
# thing anyway
require 'readline'
# the actualy mlmp3p player
require 'player'

# Keep everything in the Mlmp3p module (along with Player)
module Mlmp3p
  class Controller
    DEBUG = false#true
    attr_reader :player
    
    # start up the command line controller
    def initialize
      puts "controller version 0.05"
      @last_long_command = nil                                   
      # also initialize a player
      @player = Mlmp3p::Player.new 
    end

    # handles keyboard controls, should be set in infinite loop so 
    # that controller always outlives any mlmp3p problems
    def control
      puts "CONTROLLER ALIVE" if DEBUG
      # set up teletype
      @mystdin = IO.open("/dev/tty") rescue IO.for_fd(2)
      while(true)
        # read a character string (one keyboard character) 
        input_char = read_char
        # execute the short command --> might lead to long command
        exec_short_command(input_char) 
      end
      ensure 
        puts "CONTROLLER DEAD" if DEBUG
    end

    # read a character with out pressing enter (probably not machine
    # independent)
    def read_char
      # Save previous state of teletype
      begin
        old_state = `stty -g`
        system "stty raw -echo"
        c = STDIN.getc.chr
        # gather next two characters of triple character keys like arrows and
        # function keys
        if(c=="\e")
          # the ESCAPE key for example is ONLY this '\e' character
          extra_thread = Thread.new{
            c = c + STDIN.getc.chr
            # not sure if there are double character keys... if so there 
            # needs to be a catch here for them
            c = c + STDIN.getc.chr
          }
          # wait just long enough for special keys to get swallowed
          #sleep(0.000000000000000000001)
          extra_thread.join(0.00001)
          extra_thread.kill
        end
      rescue => ex
        puts "#{ex.class}: #{ex.message}"
        puts ex.backtrace
      ensure 
        # restore previous state
        system "stty #{old_state}"
      end
      #system "stty -raw echo"
      return c
    end

    # takes a single character command
    def exec_short_command(command)  
        # be sure to get just one char string
        # command = command[0,1]
        # return if (command.length<1 || command=="\n")
        # carriage return and clear line
        print_and_flush "\r\e[0K"

        case command
        when "0"
          @player.adjust_volume(1)
        when "9"
          @player.adjust_volume(-1)
        when "A"
          @player.remove_all_except_current_album
        when "a"
          @player.remove_all_except_current_artist
        when "b"
          @player.reverse_and_play_track
        when "C"
          if(@player.caching and @player.force_caching)
            # turn off force caching (and caching)
            @player.toggle_force_caching
          elsif(@player.caching)
            # turn on force caching
            @player.toggle_force_caching
          else
            # turn on caching
            @player.toggle_caching
          end
        when "c"
          @player.playlist_stats
        when "e"
          @player.current_elapsed
        when "E"
          @player.show_full_path_in_info = !@player.show_full_path_in_info
            puts "Show full path in info: #{
              @player.bool2onoff(@player.show_full_path_in_info)}..."
            puts ""
        when "f"
          if !@player.current_track.nil?
            @player.current_track.skipped = @player.current_track.skipped + 1
            @player.append_track_stats(false)
          end
          @player.advance_and_play_track
        when "H"
          help
        when "h"
          help
        when "I"
          if(@player.default_regex_options =~ /i/)
            @player.default_regex_options.gsub!(/i/,"")
            puts "Default regex behavior switched to match case..."
            puts ""
          else
            @player.default_regex_options ||= ""
            @player.default_regex_options += "i"
            puts "Default regex behavior switched to ignore case..."
            puts ""
          end 
        when "i"
          @player.current_info
        when "L"
          @player.toggle_loop_track
        when "l"
          @player.toggle_loop_playlist
        when "o"
          @player.restore_original_playlist
        when "P"
          @player.current_playlist_info(true)
        when "p"
          @player.current_playlist_info
        when "Q"
          @player.exit
        when "q"
          @player.exit
        when "r"
          @player.toggle_random
        when "S"
          @player.played_tracks_info
        when "s"
          @player.sort_tracks_iTunes_style
        when "t"
          @player.jump_to_top_of_playlist
        when "z"
          @player.shuffle_tracks_array
        when " "
          @player.toggle_pause
        when "\t"
          @player.show_next_n_tracks 10
        when "&"
          exec_long_command(@last_long_command)
        when ":"
          # long command mode
          #print ":"
          #if not @pause_import 
          #  puts "Importing paused while typing command..." 
          #end 
          # flush STDOUT so that colon is sure to print BEFORE .gets is called
          @player.progress_bar = false;
          STDOUT.flush
          #kb_input = STDIN.gets
          #exec_long_command(kb_input.gsub!(/\n$/,""))

          #brandon
          #kb_input = Readline::readline(":", use_history=true)


          kb_input = nil
          readline_thread = Thread.new{
            # pause importing while entering long command
            #old_pause_import = @pause_import
            #@pause_import = true
            kb_input = Readline::readline(":", use_history=true)
            #@pause_import = old_pause_import
          }
          readline_thread.priority=-1
          @player.readline_thread = readline_thread
          readline_thread.join
         #while(kb_input.nil?)
         #  sleep(0.1)
         #end
         exec_long_command(kb_input)
         @player.progress_bar = true;
        when "\r"
          puts ""
          #do nothing
        when "\n"
          puts ""
          #do nothing
        when "\e"
          puts "ESCAPE"
        # up arrow
        when "\e[A"
          @player.seek(60.0)
        # down arrow
        when "\e[B"
          @player.seek(-60.0)
        # right arrow
        when "\e[C"
          @player.seek(10.0)
        # left arrow
        when "\e[D"
          @player.seek(-10.0)
        when "\177"
          puts "BACKSPACE"
        when "\003"
          @player.exit
        when "\004"
          puts "DELETE"
        else
          # Rewind STDIN so that double char keyboard hits like ^C etc.
          # don't count as two commands
          #STDIN.rewind
          #command = command=~/\w/ ? command : "?"
          puts "#{command.inspect} is not a known keyboard command."+ 
               " Press h for help."
        end
    end
    
    # takes a multi character command
    def exec_long_command(command)
      # save last command, just for '&' shortcut, readline already has stack of
      # previous entries for browsing
      @last_long_command = command
      
      case command
      # add path.mp3
      # add path/to/dir/
      # add -r path/to/dir/
      # add -rR path/to/dir/
      when /^\s*add(\s+\-([\w]+))?\s+(.*)/
        line = $3
        options = $2
        if(File.directory?(line))
          puts ""
          add_thread=Thread.new{
            @player.import_directory(line,options=~/r/,options=~/R/)
          }
          add_thread.priority = -2
        else
          puts ""
          Thread.new{
            @player.import_track(line, false)
          }
        end
      when /^\s*authenticate\s*$/
        authenticate
      when /^\s*cache\s+-(f|-force)\s*$/
        @player.toggle_force_caching
      when /^\s*cache\s*$/
        @player.toggle_caching
      # import paths.dat
      # import tracks.xml
      when /^\s*(default regex options|dro)\s+(.*)$/
        @player.default_regex_options = $1.strip
      when /^\s*import\s+(.*)/
        file_name = $1
        file_name = $1 if (file_name =~ /"(.*)"/)
        Thread.new {
          begin
            if file_name =~ /\.xml$/
              @player.load_xml_playlist file_name
            else 
              @player.import_playlist(File.new(file_name).read.split("\n"))
            end
          rescue => ex
            puts "#{ex.class}: #{ex.message}"
            puts ex.backtrace
          end
        }
      # jump 10
      # jump -10
      when /^\s*jump\s+(\-?[0-9]+)\s*$/
        amount = $1.to_i
        if(amount>0)
          @player.advance_and_play_track(amount)
        else
          @player.reverse_and_play_track(amount.abs+1)
        end
      # switch to mpg123
      when /^\s*mpg123\s*(\s+-f|\s+--force)?\s*$/
        if(@player.player==:mplayer)
          if(@player.available_players.include? :mpg123)
            @player.init_mpg123
            @player.player = :mpg123
            if(@player.playing)
              @player.kill_mplayer
              @player.play_track
            end
            puts "Player switched to mpg123"
          else
            puts "mpg123 not available..."
          end
        elsif($1.nil?)
          puts "Already using mpg123 as player..."
        else
          puts "Forcing mpg123 as player..."
          @player.mpg123.close unless 
            @player.mpg123.nil? || @player.mpg123.closed?
          @player.kill_mplayer
          @player.init_mpg123
          @player.player = :mpg123
          if(@player.playing)
            @player.play_track
          end
        end
      # switch to mplayer
      when /^\s*mplayer\s*(\s+-f|\s+--force)?\s*$/
        if(@player.player==:mpg123)
          if(@player.available_players.include? :mplayer)
            @player.init_mplayer
            @player.player = :mplayer
            @player.mpg123.close unless 
              @player.mpg123.nil? || @player.mpg123.closed?
            if(@player.playing)
              @player.playing = false
              @player.play_track
            end
            puts "Player switched to mplayer"
          else
            puts "mplayer not available..."
          end
        elsif($1.nil?)
          puts "Already using mplayer as player..."
        else
          puts "Forcing mplayer as player..."
          @player.mpg123.close unless 
            @player.mpg123.nil? || @player.mpg123.closed?
          @player.kill_mplayer
          @player.init_mplayer
          @player.player = :mplayer
          if(@player.playing)
            @player.playing = false
            @player.play_track
          end
        end
      when /^\s*next\s+([0-9]+)\s*$/
        @player.show_next_n_tracks Integer($1) 
      when /^\s*pause\s+import\s*$/
        @player.toggle_pause_import
      when /^\s*play\s+(.*)/
        file_name = $1
        file_name = $1 if (file_name =~ /"(.*)"/)
        @player.find_by_path_and_play(file_name)
      when /^\s*(q(uit)?|exit)\s*$/i
        @player.exit
      when /^\s*restart\s*$/
        if(@player.player == :mplayer)
          puts "Restarting mplayer..."
          @player.kill_mplayer
          @player.init_mplayer
          @player.play_track
        elsif(@player.player == :mpg123)
          puts "Restarting mpg123..."
          @player.mpg123.close unless 
            @player.mpg123.nil? || @player.mpg123.closed?
          @player.init_mpg123
        end
      when /^\s*unsleep\s*$/
        puts ""
        if(@player.sleep_timestamp.nil?)
          puts "No sleep to cancel..."
        else
          @player.sleep_timestamp = nil
          puts "Sleep cancelled..."
        end
      when /^\s*sleep\s+(\d+)\s*([mhsd])?\s*$/
        puts ""
        amount = $1.to_i
        case $2
          when "m"
            amount = 60*amount
          when "h"
            amount = 60*60*amount
          when "s"
            amount = amount
          when "d"
            amount = 24*60*60*amount
        end
        @player.set_sleep amount
        puts "Will automatically exit in #{@player.sleep_amount} seconds..."
      when /^\s*sort((\s+\w+)+)/
        puts ""
        @player.sort_tracks @player.tracks_array, 
          $1.split(" ").collect{|f| f.strip}
      when /^\s*state\s*$/
        @player.playlist_stats(true)
      when /^\s*xml\s+(.*)/
        file_name = $1
        file_name = $1 if (file_name =~ /"(.*)"/)
        xml_thread = Thread.new{
          puts "xml thread begun..."
          @player.write_tracks_array_to_xml_file(
            @player.tracks_array.clone,file_name.strip)
        }
        xml_thread.priority = -2
      when /^\s*(\w)?\/(.*?)\/(\w+?)(\/(\w?))?(\s*|\s+(\-?[0-9]+))\s*$/
        case $1
        when "p"
          @player.play_next_track_matching_given_regex_from_given_field(
            $2,$3,$5)
        when "q"
          if $7.nil?
            offset = 1
          else
            # convert string to number
            offset = $7.to_i
          end
          @player.queue_next_track_matching_given_regex_from_given_field(
            $2,$3,offset,$5)
        when "r"
          @player.remove_all_except_given_regex_from_given_field($2,$3,$5)
        when nil
          @player.show_tracks_matching_given_regex_from_given_field($2,$3,$5)
        end
      when /^\s*$/ 
        #do nothing
      else
        print_and_flush "\r\e[0K"
        #mpg123_send_command(command)
        puts "#{command} is not a known long " +
              "keyboard command. Press h for help."
      end
    end

    def authenticate
      print_and_flush "User: "
      @player.user = read_line
      print_and_flush "Password: "
      @player.password = read_line(echo=false)
      puts ""
    end
      
    # Does not use Readline
    # 
    def read_line(echo=true)
      line = ""
      # Save previous state
      begin
        old_state = `stty -g`
        if echo
          system "stty echo" 
        else
          system "stty -echo" 
        end 
        line = STDIN.gets
      rescue => ex
        puts "#{ex.class}: #{ex.message}"
        puts ex.backtrace
      ensure 
        # restore previous stty state
        system "stty #{old_state}"
      end
      return line.strip
    end
    
        def help
      puts ""
      help_document = <<HERE
= Keyboard shortcuts (single key commands) =
Q,q      quit
[space]  pause/unpause
f        advance forward a track
b        reverse to beginnging of track. If at beginning, reverse a track
z        shuffle current playlist, rearrange order of playlist then play
         tracks sequentially in shuffled order. Not pick a song at random
         each time.
r        choose next track at random. Differs from shuffle (z) because
         playlist is not shuffled.
i        show info about current track
p        show current playlist
P        show detailed current playlist
s        sort tracks by artist, then album, then path (track number)
S        show stack of already played tracks
o        restore original playlist
a        remove all tracks from playlist except those of current artist
A        remove all tracks from playlist except those of current album
l        repeat playlist (loop), default is ON
L        repeat current track (loop), default is OFF
e        show time elapsed since starting current track
I        toggle regex match or ignore case 
c        show player statistics
0        increase volume
9        decrease volume
E        toggle showing full path of track
t        jump to top of current playlist
C        toggle through caching options, ON, FORCE, OFF
[tab]    show next 10 songs
H,h      this help document
:        begin a long command (see below)
&        repeat the last long command issued

= Long commands =
:xml [path to file]    Saves the current playlist as an xml document in the
                       given file.
:sort [fields]         Sort current playlist by given fields in order. For 
                       example, :sort artist path would sort the current 
                       playlist by artist then path.
:pause import          Toggle importing from a mp3-path-list file (not XML). 
                       Useful if importing mp3s from a long list (thousands) 
                       of mp3s: allows a drive to catch her breath. 
:jump [integer]        Jump forward n tracks (or back -n tracks if given n is
                       negative).
:next [integer]        Shows the next n tracks on the current playlist, 
                       assuming not random since that is done dynamically.
:/[regex]/[field]      Show all matches to the given regex in the given field
                       from the current playlist. :/^Black.*/artist/ will show
                       songs with artist starting with "Black".
                       Additionally options maybe given after the field.
                       /i  ignore case
                       /v  reverse results
                       So, :/^black.*/artist/i will show songs with artist 
                       starting with "black" ignoring case.
:r/[regex]/[field]     Remove all but matches to given regex in the given field
                       from current playlist. For example, :r/Black Keys/artist
                       would remove all tracks from the playlist whose artist 
                       field did not contain "Black Keys". Use Ruby (Perl) 
                       syntax for regular expressions.
:p/[regex]/[field]     Plays the first track in the playlist that matches the 
                       given regex in the given field. For example, 
                       :p/Bad Days/title would play the first track with 
                       "Bad Days" in the title.
:q/[regex]/[field]     Queues the first track in the playlist that matches the 
                       given regex in the given field. For example, 
                       :q/Bad Days/title would make the next track the first
                       track found  with "Bad Days" in the title.
:state                 Show information and stats about the player
:import [path to file] Import tracks to the current playlist from a file 
                       containing a list of paths to mp3 files or an xml file.
:add [-r] [path]       Add track to current playlist from a given path to mp3 
                       file or add tracks from a given directory path with 
                       recursive option -r.
:dro [new dro]         Specify dro (default regex options) with a string of
                       regex options characters: ivmx or empty.
:sleep [number]        Automatically exit after [number] seconds, use d,h, or m
                       to specify other units.
:unsleep               Cancel sleep command
:mplayer [-f|--force]  Switch player to mplayer (/usr/bin/mplayer), -f forces
                       mplayer to restart
:mpg123 [-f|--force]   Switch player to mpg123 (/usr/bin/mpg123), -f forces
                       mpg123 to restart
:cache [-f]            toggle caching, option -f forces caching
HERE
      puts help_document
    end

    def puts object
      print_and_flush "#{object}\r\n"
    end

    def print_and_flush object
      print "#{object}"
      $stdout.flush()
    end

  
  end
end

__END__

