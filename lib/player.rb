#!/opt/local/bin/ruby -w
#!/usr/local/bin/ruby -w
# mlmp3p
# a Ruby wrapper for mplayer or mpg123 
# mp3 controller, player, server
# Version: 0.06
# Author: Alec Jacobson (alecjacobson@gmail.com)
#
#
#

class IO

  attr_accessor :rlnb_buffer

  def readline_nonblock
    if @rlnb_buffer.nil?
      @rlnb_buffer = ""
    end
    begin
      while(true)
        nl_index = @rlnb_buffer.index("\n")
        if not nl_index.nil?
          front = @rlnb_buffer[0..nl_index]
          @rlnb_buffer = @rlnb_buffer[nl_index+1..-1]
          return front
        end
        @rlnb_buffer << self.read_nonblock(100)
      end     
    rescue Errno::EAGAIN => e
      return ""
    end
  end     

  def readall_nonblock
    ranb_buffer = ""
    begin
      while ch = self.read_nonblock(1000) 
        ranb_buffer << ch
      end     
    rescue Errno::EAGAIN => e
      return ranb_buffer
    end
  end     

end      

# should be included with standard ruby
require 'open-uri'
# should be included with standard ruby, needed to escape and unescape paths
require 'uri'
# Ruby gems can be found at: http://rubygems.org/
#this is wrong? # sudo apt-get install ruby1.8-dev
require "rubygems"
# sudo gem install ruby-mp3info
require 'mp3info'
# sudo gem install builder
require 'builder'
# sudo apt-get install libxml2-dev
# sudo gem install libxml-ruby
require 'libxml'
# for copying files
require 'ftools'
# for timestamps
require 'time'
  
module Mlmp3p
  # class for each track, basic information and weighting for smart random
  class Track
    FIELD_KEYS = ["weight","path","tag","played","skipped"]
    TAG_KEYS = ["artist","album","title","genre","year","comments"]
    attr_accessor :relative_path
    attr_accessor :cache_path
    attr_accessor :weight
    attr_accessor :played #play count
    attr_accessor :skipped #skip count
    attr_accessor :tag # hash to hold id3v2 info
    attr_accessor :root_dir # root dir defined in playlist
    attr_accessor :absolute_path_to_playlist_dir # path to dir containing playlist

    def initialize
      @absolute_path_to_playlist_dir = nil
      @played = 0
      @skipped = 0
    end

    def prefix
      if(not @absolute_path_to_playlist_dir.nil? and not @root_dir.nil?)
        # if root dir looks like an absolute path then use that
        if(@root_dir =~ /^\//)
          return @root_dir
        elsif(@absolute_path_to_playlist_dir =~ /#{Regexp.escape(@root_dir)}/)
          return @absolute_path_to_playlist_dir
        elsif(@root_dir=~ /#{Regexp.escape(@absolute_path_to_playlist_dir)}/)
          return @root_dir
        else 
          return File.join(@absolute_path_to_playlist_dir,@root_dir)
        end
      elsif(not @root_dir.nil?)
        return @root_dir
      elsif(not @absolute_path_to_playlist_dir.nil?)
        return @absolute_path_to_playlist_dir
      else
        return ""
      end
    end

    def path
      return File.join(prefix,@relative_path)
    end

    def decrease_weight
      @weight = @weight / 2.0
      @weight = (@weight < 0.0 ? 0.0 : @weight)
    end

    def increase_weight
      @weight = @weight * 2.0
      @weight = (@weight > 1.0 ? 1.0 : @weight)
    end

  end

  # class for playing and controlling mp3s using mplayer or mpg123
  class Player
    # for a few informational debug messages
    DEBUG = false#true
    #DEBUG = true
    VERBOSE_DEBUG = false
    # http://www.mplayerhq.hu/design7/dload.html
    # For Mac OS X mplayer can be found at:
    # /Applications/MPlayer\ OSX.app/Contents/Resources/External_Binaries/mplayer.app/Contents/MacOS/mplayer 
    # Do NOT use MPlayer OSX 2
    #MPLAYER_PATH = "/usr/bin/mplayer"
    MPLAYER_PATH = `which mplayer`.strip
    ## sudo apt-get install mpg123
    #MPG123_PATH = "/usr/bin/mpg123"
    MPG123_PATH = `which mpg123`.strip
    attr_accessor :current_track_index  
    attr_accessor :loop_playlist # play through tracks once or loop for ininity
    attr_accessor :loop_track # play through tracks once or loop for ininity
    attr_accessor :password  # for now just keep one password not encrypted
    attr_accessor :pause_import
    attr_accessor :player # either :mplayer or :mpg123
    attr_accessor :random # get next song randomly?
    attr_accessor :user # for now just keep one user not encrypted
    attr_reader :current_track 
    attr_reader :original_tracks_array
    attr_reader :played_tracks # stack of played tracks
    attr_reader :shuffled #
    attr_reader :using_originals #
    attr_reader :available_players
    attr_accessor :playing # is mplayer or mpg123 instance currently playing a song
    attr_reader :tracks_array # array of tracks (track objects)
    attr_accessor :xml_file_name # overwriteable xml file name
    attr_accessor :sleep_timestamp 
    attr_accessor :sleep_warned
    attr_accessor :sleep_amount
    attr_accessor :readline_thread
    attr_accessor :mplayer
    attr_accessor :mpg123
    attr_accessor :default_regex_options
    attr_accessor :show_full_path_in_info
    attr_reader :caching
    attr_reader :force_caching
    
    
    # initialize the mplayer or mpg123 player
    def initialize
      puts "player version 0.06"
      @available_players = check_for_players #hardcode mplayer for now...
      if(@available_players.empty?)
        puts "No available players... check paths... exiting..."
        Process.exit 
      end
      @player = @available_players.first
      if(@player==:mpg123)
        # redirect all of the output from mpg123 to /dev/null
        #redirect_output = " 2> /dev/null"
        init_mpg123
      else
        puts "Using mplayer..." if DEBUG
        init_mplayer
      end
      @advance_thread = nil   
      @cache_directory = ".cache"
      @cache_thread = nil
      @mute_thread = nil
      @paused_on_mute = false
      @caching = true                            
      @force_caching = false
      puts "Caching ON..." if DEBUG
      @current_track = nil                                       
      @current_track_index = nil                                 
      @loop_playlist = true                                      
      @loop_track= false                                         
      @mplayer_loading = false
      @mutex = 1                                        
      @original_tracks_array = []
      @password = nil
      @pause_import = false                                      
      @played_tracks = [] # stack for played songs
      @playing = false # not playing currently               
      @random = false                                            
      @shuffled = false                                            
      @tracks_array = []
      @user = nil
      @using_originals = true       
      @readline_thread = nil
      @default_regex_options = "i" # default to ignore case
      @show_full_path_in_info = false
      @sleep_timestamp = nil
      @sleep_amount = nil
      @sleep_warned = false
      @xml_file_name = nil
    end

    def check_for_players
      players = []
      mplayer_path = MPLAYER_PATH
      mplayer_path = '/usr/local/bin/mplayer' if mplayer_path.empty?
      if( FileTest::executable_real?(mplayer_path) )
        players << :mplayer
      else
        mplayer_path = '/opt/local/bin/mplayer'
        if( FileTest::executable_real?(mplayer_path) )
          players << :mplayer
        else
          puts "#{mplayer_path} doesn't appear to exist..." if DEBUG
        end
      end
      if( FileTest::executable_real?(MPG123_PATH) )
        players << :mpg123
      else 
        puts "#{MPG123_PATH} doesn't appear to exist..." if DEBUG
      end
      return players
    end

    # Start up the mpg123 process
    def init_mpg123
        redirect_output = "2&>1 >/dev/null"
        redirect_output = "2> /dev/null"
        @mpg123 = IO::popen("#{MPG123_PATH} -q -R - #{redirect_output}", 'r+')
    end

    # Start up the mplayer process    
    def init_mplayer
        #redirect_output = "2&>1 >/dev/null"
        #redirect_output = "2> /dev/null"
        redirect_output = "2>&1"
        ##-noconsolecontrols   ignore keyboard shortcuts from stdin
        ##-idle                open and sit
        ##-slave               accept slave input commands, see 
        ##                     mplayer -input cmdlist
        #options = "-noconsolecontrols -idle -slave"+
        #  " -msglevel statusline=6 -msglevel global=6"
        #@mplayer = IO::popen("#{MPLAYER_PATH} #{options} #{redirect_output}", 
        #  'r+')
      options = "-quiet -noconsolecontrols -nolirc -idle -slave  -msglevel statusline=6 -msglevel global=6"
      @mplayer = IO.popen("#{MPLAYER_PATH} #{options} #{redirect_output}","w+")
    end
    
    # make sure mplayer isn't still alive
    def kill_mplayer
      if((!@mplayer.nil?) && (!@mplayer.closed?))
          begin 
            mplayer_send_command("quit") 
          rescue Errno::EPIPE 
            puts "Mplayer did not quit"
          end
          # .close is slow...because its waiting on popen to finish mplayer
          # start up!!, how about commenting it out?
          temp_mplayer = @mplayer # need a copy of THIS instance
          temp_mplayer.close 
          if(not temp_mplayer.closed?)
            puts "ERROR: mplayer did not close properly..."
          end
      else
        puts "Didn't quit mplayer because it already closed? ..."
      end
    end

    # Display time since song was started...not how much of songs has elapsed
    def current_elapsed
      if not @current_track_start_time.nil?
        seconds = Time.now-@current_track_start_time
        minutes = (seconds / 60).to_i
        seconds = (seconds - minutes*60).to_i
        puts ""
        puts "Current track has been playing for #{minutes}m#{seconds}s"
      end
    end

    # find the next track that matches the given path and play it
    def find_by_path_and_play(path)
      track = find_by_path(path)
      if track
        @current_track = track
        play_track
      else
        puts "No track found at path: #{path}"
      end
    end

    def find_by_path(path)
      @tracks_array.find{|track| track.path==path}
    end

    # print out the next 10 tracks (assuming not random...)
    def show_next_n_tracks(n, verbose=false)
      if @tracks_array.length == 0
        puts "Playlist empty. No tracks to show."
      else
        puts "" 
        puts "= Next #{n} tracks on current playlist =" 
        @current_track_index = @tracks_array.index @current_track
        @current_track_index = 0 if @current_track_index.nil?
        show_tracks_m_through_n(
          @tracks_array,
          @current_track_index+1,
          @current_track_index+n+1, 
          verbose)
      end
    end
    
    # show info for the tracks indexed between given m and n
    def show_tracks_m_through_n(playlist, m, n, verbose=false)
      # if not looping then clip the request to the length of the array
      return false if playlist.length == 0
      n = playlist.length if ! loop_playlist and n> playlist.length
      (m...n).each do |i|
        # modding the index  for looping playlist
        i = (i+playlist.length) % playlist.length
        if (verbose)
          info playlist[i]
        else
          track_path = playlist[i].path
          if(not @show_full_path_in_info)
            prefix = Regexp.escape(playlist[i].prefix)
            track_path = track_path.gsub(/^#{prefix}/,"")
          end
          puts track_path
        end
      end
    end

    # sort tracks by artist then album then path (like iTunes)
    def sort_tracks_iTunes_style
      puts ""
      sort_tracks @tracks_array, ["artist","album","path"]
    end


    
    # sort a given playlist by given fields
    # fields are given as an array of track fields and track tag fields
    def sort_tracks(playlist, original_fields)
      fields = original_fields.collect{|f| f.downcase}.select do |f| 
        Track::TAG_KEYS.include?(f) || Track::FIELD_KEYS.include?(f)
      end
      rejected = original_fields-fields
      puts "Invalid fields: #{rejected.join(", ")}" if not rejected.empty?
      if fields.empty?
        puts "Can't sort because no given fields were valid."
      else
        print_and_flush "Sorting..."
        new_playlist = playlist.sort_by do |track|
          order = []
          fields.each do |field|
            value = ""
            if field=="path"
              value = track.path
            elsif field == "weight"
              value = track.weight
            elsif field == "played"
              value = -track.played
            elsif field == "skipped"
              value = -track.skipped
            else
              value = track.tag[field.intern] 
              # remove any primary "the "s
              value.gsub(/^the\s+/i,"") unless value.nil?
            end
            value ||= ""
            order << value
          end
          order
        end
        set_tracks_array new_playlist
        print_and_flush "\r\e[0K"
        @shuffled = false
        puts "Current playlist sorted by #{fields.join(" then ")}"
      end
    end
    
    def bool2onoff(bool)
      bool ? "ON" : "OFF"
    end
    
    def playlist_stats(verbose=false)
      puts ""
      if(verbose)
        puts "Using original playlist: #{bool2onoff(@using_originals)}"
        puts "Repeat playlist: #{bool2onoff(@loop_playlist)}"
        puts "Repeat track: #{bool2onoff(@loop_track)}"
        puts "Importing paused: #{bool2onoff(@pause_import)}"
        puts "Random: #{bool2onoff(@random)}"
        puts "Shuffled: #{bool2onoff(@shuffled)}"
        puts "Caching: #{bool2onoff(@caching)}"
        puts "Current track path: #{@current_track.path}"
        puts "Current track index: #{@current_track_index}"
        puts "Playing: #{bool2onoff(@playing)}"
        puts "Default regex options: " +
          ((@default_regex_options.empty? || @default_regex_options.nil?) ? 
            "empty" : @default_regex_options)
      end
      puts "There are #{@tracks_array.length} tracks in the current playlist."
    end

    # kill process, there's probably a gentler way to do this
    def exit
      if(@player==:mplayer)
        kill_mplayer
      end
      Process.exit
    end

    def toggle_force_caching
      @force_caching = !@force_caching
      @caching = @force_caching
      if @force_caching
        puts ""
        puts "Force caching ON." 
      else
        puts ""
        puts "Force caching OFF."
      end
    end

    def toggle_caching
      @caching = !@caching
      if @caching
        puts ""
        puts "Caching ON." 
      else
        puts ""
        puts "Caching OFF."
      end
    end

    def toggle_random
      @random = !@random
      if @random
        puts ""
        puts "Random advance ON." 
      else
        puts ""
        puts "Random advance OFF."
      end
    end
    
    def toggle_loop_track
      @loop_track = !@loop_track
      if @loop_track
        puts ""
        puts "Repeat track ON." 
      else
        puts ""
        puts "Repeat track OFF."
      end
    end

    
    def toggle_loop_playlist
      @loop_playlist = !@loop_playlist;
      if @loop_playlist
        puts ""
        puts "Repeat playlist ON." 
      else
        puts ""
        puts "Repeat playlist OFF."
      end
    end

    # shuffle the tracks in the tracks array
    # destructive to @tracks_array
    def shuffle_tracks_array
      print_and_flush "Shuffling..."
      set_tracks_array @tracks_array.sort_by{rand}
      print_and_flush "\r\e[0K"
      @shuffled = true
      puts "Current playlist shuffled."
    end
    
    # start playing the current play list
    def start
      # don't start trying to play until there are some files to play
      while(@tracks_array.nil? || @tracks_array.empty?)
        sleep(0.1)
      end
      
      # wait for a few more songs
      sleep(0.5)
      shuffle_tracks_array
      
      play_track
      # loop until out of songs 
      mplayer_results = ""
      while(true)
        
        if(@playing)
          if(@player==:mpg123)
            begin
              mpg123_results = @mpg123.readline.chop()
            rescue EOFError
              puts "mpg123 error... perhaps track path did not exist..."
            rescue IOError
              #puts "mpg123 error... probably closed stream"
            end 

            #puts mpg123_results

            #show track information
            if( mpg123_results =~ /^@I\s+ID3:(.*)$/)
              mp3tag = @current_track.tag
              @title = $1[0,30]
              @artist = $1[30,30]
              @album = $1[60,30]
              @year = $1[90,4]
              @comment = $1[94,30]
              @genre  = $1[124,$1.length-124]
              #puts "  Title: #{@title  } Artist: #{@artist}"
              #puts "  Album: #{@album  }   Year: #{@year  }"
              #puts "Comment: #{@comment}  Genre: #{@genre  }"
              if( not mp3tag.nil?)
                #mp3tag[:title] = @title if(! @title.nil? && mp3tag[:title].nil?)
                #mp3tag[:artist] = @artist if(! @artist.nil? && mp3tag[:artist].nil?)
                #mp3tag[:album] = @album if(! @album.nil? && mp3tag[:album].nil?)
                #mp3tag[:year] = @artist if(! @year.nil? && mp3tag[:year].nil?)
                #mp3tag[:comment] = @comment if(! @comment.nil? && mp3tag[:comment].nil?)
                #mp3tag[:genre] = @genre if(! @genre.nil? && mp3tag[:genre].nil?)
              end
              #current_info
            elsif( mpg123_results =~ /^@I\s+(.*)$/) 
              #puts $1
            end

            # Change to the next song if current song stops and the user didn't told it to
            if(mpg123_results =~ /^@P 0/)
              on_track_finished
              # Song stopped, so advance
              advance unless @loop_track
              play_track
            end
          elsif(@player==:mplayer && !@mplayer_loading) 
          # using mplayer and mplayer not loading

            mplayer_results << @mplayer.readline_nonblock
            if mplayer_results.length > 0 && mplayer_results[-1] == "\n"
              #print_and_flush mplayer_results
              #puts "Mplayer says '#{mplayer_results}'"
              # regexps from ruby-mplayer:
              # http://github.com/CodeMonkeySteve/ruby-mplayer
              case mplayer_results
              when %r{^Playing (.*)\.\n$}
                track_name = $1
                #puts "Track name: #{track_name}"
              when %r{^A: \s*([\d]+\.[\d]+) .* of \s*([\d]+\.[\d]+) }
                position = $1.to_f
                length = $2.to_f
                #puts "Position: #{position} Length: #{length}"
              when %r{^Name: (.*)\s*\n$}        then  title = $1
              when %r{^Album: (.*)\s*\n$}       then  album = $1
              when %r{^Track: (.*)\s*\n$}       then  num = $1.to_i
              when /=====  PAUSE  =====/
                #@playing = false
                #puts "Pause on mplayer"
                sleep(0.1)
              #when "\n"
              when %r{^EOF code: (.*)\s*\n$}
                on_track_finished
                #puts "advancing..."
                if( not @mplayer_loading)
                  @playing = false
                  puts "main play loop about to advance" if VERBOSE_DEBUG
                  advance unless @loop_track
                  puts "main play loop about to play" if VERBOSE_DEBUG
                  play_track
                  puts "main play loop just played" if VERBOSE_DEBUG
                else
                  puts "@mplayer_loading: #{@mplayer_loading} so not advancing..." if VERBOSE_DEBUG
                end
              else
                #puts "Mplayer says '#{mplayer_results}'"
              end
              #if(not @mplayer.nil?)
              #  begin
              #    # mplayer will sit on this .all? method until song is done
              #    @mplayer.all?
              #    advance if(not @loop_track)
              #    play_track
              #  rescue IOError
              #  end
              #end
              mplayer_results = ""
            else 
              sleep(0.1)
            end
          else
            #puts "@mplayer_loading: #{@mplayer_loading} so not playing?..." if VERBOSE_DEBUG
          end  
          $stdout.flush()
        else
          sleep(0.1)
        end 
        
        # check if should quit for sleep function
        if(!@sleep_timestamp.nil? &&
          Time.now - @sleep_timestamp > @sleep_amount)
          puts "Automatically exitting..."
          exit
        elsif(!@sleep_timestamp.nil? &&
          @sleep_amount > 10 &&
          Time.now - @sleep_timestamp > @sleep_amount-10 &&
          !@sleep_warned)
          @sleep_warned = true
          puts "About to automatically exit, cancel with :unsleep"
        end

        ## check if should pause if muted
        #if @mute_thread.nil? or not @mute_thread.alive?
        #  @mute_thread = Thread.new do 
        #    effective_volume = `volume`.to_f;
        #    is_muted = effective_volume==0;
        #    #is_muted = `osascript -e "output muted of (get volume settings)"`.strip 
        #    if is_muted == "true"
        #      if @playing
        #        toggle_pause
        #        @paused_on_mute = true
        #      end
        #    elsif @paused_on_mute and not @playing
        #      # unpause if no longer muted and had previously paused becuase of
        #      # mute
        #      toggle_pause
        #    end
        #    sleep(0.5)
        #  end
        #  @mute_thread.priority = -10
        #end
      end
    end
    
    def set_sleep(amount)
      @sleep_timestamp = Time.now
      @sleep_amount = amount
      @sleep_warned = false
    end

    # read a "line" from mplayer's output... "line" ends in either a 
    # \n or a \r, returned value includes final \r or \n 
    def mplayer_readline
      begin
        str = ""
        while((c=@mplayer.read 1) !~ /[\n\r]/)
          str = str + c
        end
        str = str + c
        #str= @mplayer.readline
      rescue IOError
        # probably closed stream
        return ""
      end
      return str
    end

    
    # Calls select_from_playlist with a regex for matching on the current
    # artist, so that the current playlist changes to a playlist only
    # containing tracks by the current artist.
    # This method is destructive to: @tracks_array
    def remove_all_except_current_artist 
      mp3tag = @current_track.tag
      if(not mp3tag.nil? and not mp3tag[:artist].nil?)
        current_artist = mp3tag[:artist] 
        # add the option to have "the" appear before artist if not already 
        current_artist.gsub!(/^the\s/i,"")
        the = "(the\s)?" 
        # be sure to escape artist in case it contains ()'s etc
        remove_all_except_given_regex_from_given_field(
          "^#{the}#{Regexp.escape(current_artist)}$", "artist","i") 
      else
        puts "Can't remove all except current artist because"+
          " mp3 info doesn't exist for this track"
      end
    end
    
    def remove_all_except_current_album
      mp3tag = @current_track.tag
      if(not mp3tag.nil? and not mp3tag[:album].nil?)
        current_artist = mp3tag[:album] 
        # be sure to escape artist in case it contains ()'s etc
        remove_all_except_given_regex_from_given_field(
          "^#{Regexp.escape(current_artist)}$", "album") 
      else
        puts "Can't remove all except current album because"+
          " mp3 info doesn't exist for this track"
      end
    end

    def show_tracks_matching_given_regex_from_given_field(
      regex, 
      field, 
      options=nil
    )
      options = @default_regex_options if( options.nil? || options.empty?)
      puts ""
      print_and_flush "Searching..."
      if not Track::TAG_KEYS.include? field
        puts "Cannot process regex because field, #{field}, does not exist"
        return false
      end
      regex_hash = {field => regex} 
      new_tracks_array = select_from_playlist(regex_hash, options)
      print_and_flush "\r\e[0K"
      if(new_tracks_array.empty?)
        puts "No matching track found for #{regex} in #{field} field."
      else
        puts "= Tracks matching #{regex} in #{field} field ="
        playlist_info new_tracks_array
      end
    end
    
    def play_next_track_matching_given_regex_from_given_field(
      regex, field,
      options=nil
      )
      options = @default_regex_options if( options.nil? || options.empty?)
      print_and_flush "Searching..."
      track = 
        next_track_matching_given_regex_from_given_field(regex, field, options)
      print_and_flush "\r\e[0K"
      if track
        @current_track = track
        play_track
      else
        puts "No matching track found for #{regex} in #{field} field."
      end
    end
    
    def queue_next_track_matching_given_regex_from_given_field(
      regex, field, offset=1,
      options=nil
      )
      if(offset.nil?)
        offset = 1
      end
      options = @default_regex_options if( options.nil? || options.empty?)
      print_and_flush "Searching..."
      track = 
        next_track_matching_given_regex_from_given_field(regex, field, options)
      print_and_flush "\r\e[0K"
      if track
        track_index = @tracks_array.index track
        @current_track_index = @tracks_array.index @current_track
        next_track_index = (@current_track_index+offset) % @tracks_array.length
        # swap tracks in tracks array
        @tracks_array[next_track_index], @tracks_array[track_index] =
          @tracks_array[track_index], @tracks_array[next_track_index]
        puts "Queued 1 track to current position + #{offset}."
        if(offset == 0)
          @current_track = @tracks_array[next_track_index]
          play_track
        end
      else
        puts "No matching track found for #{regex} in #{field} field."
      end
    end

    # given string regex and options give results for corresponding regex 
    # operation
    def match(string, regex,
      options=nil
      )
      options = @default_regex_options if( options.nil? || options.empty?)
      case options
      when "i"
        return string =~ /#{regex}/i
      when "m"
        return string =~ /#{regex}/m
      when "x"
        return string =~ /#{regex}/x
      when "v"
        return string !~ /#{regex}/
      when "vi"
        return string !~ /#{regex}/i
      when "iv"
        return string !~ /#{regex}/i
      when nil
        return string =~ /#{regex}/
      end
      # just return as if no options given
      return string =~ /#{regex}/
    end
    
    def next_track_matching_given_regex_from_given_field(regex, field, 
      options=nil
      )
      options = @default_regex_options if( options.nil? || options.empty?)
      if not Track::TAG_KEYS.include? field
        puts "Cannot process regex because field, #{field}, does not exist"
        return false
      end
      # current song should come before next track found
      minimum_index = @current_track_index
      minimum_index ||= -1 # just in case @current_track_index was nil
      first_before_index = nil
      @tracks_array.each_with_index do |track, i|
        if match(track.tag[field.intern],regex, options)
          if i>minimum_index
            return track
          elsif first_before_index.nil?
            first_before_index = i
          end
        end
      end

      # if track wasn't found after current track then return first track on
      # playlist before the current track 
      # and looping must be on?
      if (not first_before_index.nil?) and (@loop_playlist)
        return @tracks_array[first_before_index]
      end

      return false
    end

    # take a regex and a field and remove all the non-matches of regex in that
    # field from current playlist
    def remove_all_except_given_regex_from_given_field(
      regex, field, 
      options=nil
      )
      options = @default_regex_options if( options.nil? || options.empty?)
      puts ""
      if not Track::TAG_KEYS.include? field
        puts "Cannot process regex because field, #{field}, does not exist"
        return false
      end
      print_and_flush "Searching..."
      regex_hash = {field => regex} 
      new_tracks_array = select_from_playlist(regex_hash, options)
      @using_originals = false
      set_tracks_array(new_tracks_array)
      print_and_flush "\r\e[0K"
      puts "Removed all but matches to #{regex} in #{field} field."
    end

    # Given hash with regexs for artist, album, title etc. select! from the 
    # current playlist only songs that match the regexs. Nils and empty string
    # decidedly match everything.
    # TODO: Be able to match artist=~ "The Black Keys" OR album=~"Maladroit"
    # This method is destructive to: @tracks_array
    def select_from_playlist(regex_hash, 
      options=nil
    )
      options = @default_regex_options if( options.nil? || options.empty?)
      #blank_regex = {"artist"=>"", "album"=>"", "title"=>"", "year"=>"","tracknum"=>"", "comments"=>"", "genre"=>""}
      #regex_hash = {}
      # Don't worry if given regex doesn't have all of the keys, but do get rid
      # of nonsense keys 
      #blank_regex.keys.each do |key|
      #  regex_hash[key] = partial_regex_hash[key].nil? ? 
      #    blank_regex[key] : partial_regex_hash[key]
      #end
      new_tracks_array = []
      index = 0
      @tracks_array.each do |track|
        mp3tag = track.tag
        keep = true
        Track::TAG_KEYS.each do |key|
          # Don't worry if given regex doesn't have all of the keys, but do get rid
          # of nonsense keys 
          regex = regex_hash[key].nil? ? "" : regex_hash[key]
          # check if tag info for this key matches regex for this key
          # "string".intern => :string
          if((!regex.empty? && !regex.nil?) &&
            (mp3tag.nil? || 
              mp3tag[key.intern].nil? || 
              !match(mp3tag[key.intern], regex, options)
            )
          )
            keep  = false 
          else
          end
        end
        if(keep)
          new_tracks_array[index] = track
          index = index + 1
        end
      end
      # return new playlist
      new_tracks_array
    end


    def set_tracks_array array
      @tracks_array = array
      # nil is okay here because advance can handle nil
      @current_track_index = @tracks_array.index @current_track
    end
    
    # This method is destructive to: @tracks_array
    def restore_original_playlist
      @using_originals = true
      if not @original_tracks_array.nil?
        set_tracks_array @original_tracks_array.clone 
        puts ""
        puts "Original playlist restored."
      else
        puts ""
        puts "Already at originals..."
      end
    end
    
    def played_tracks_info(verbose=false)
      puts ""
      puts "= Stack of Already Played Tracks ="
      @played_tracks.each do |track|
        if(verbose)
            info track
        else
          puts track.path
        end
      end
    end
    
    def current_playlist_info(verbose=false)
      puts ""
      puts "= Current Playlist ="
      playlist_info(@tracks_array, verbose)
    end
    
    def playlist_info(playlist, verbose=false)
      show_tracks_m_through_n(playlist, 0,playlist.length,verbose)
    end
    
    def current_info
      info @current_track 
    end
    
    def info(track)
      puts ""
      if !track.nil?
        mp3tag = track.tag
        if mp3tag.nil?
          #puts "Title:   "+@title if (not @title.nil?)
          #puts "Artist:  "+@artist if (not @artist.nil?)
          #puts "Ablum:   "+@album if (not @album.nil?)
          #puts "Year:    "+@year if (not @year.nil?)
          #puts "Comment: "+@comment if (not @comment.nil?)
          #puts "Genre:   "+@genre if (not @genre.nil?)
        end
        if not mp3tag.nil?
          puts "Title:   #{mp3tag[:title]}" if (not mp3tag[:title].nil?)
          puts "Artist:  #{mp3tag[:artist]}" if (not mp3tag[:artist].nil?)
          puts "Ablum:   #{mp3tag[:album]}" if (not mp3tag[:album].nil?)
          puts "Year:    #{mp3tag[:year]}" if (not mp3tag[:year].nil?)
          puts "Comment: #{mp3tag[:comment]}" if (not mp3tag[:comment].nil?)
          puts "Genre:   #{mp3tag[:genre]}" if (not mp3tag[:genre].nil?)
        end
        puts "Cache:   #{track.cache_path}" unless(track.cache_path.nil?)
        track_path = track.path
        if(not @show_full_path_in_info)
          prefix = Regexp.escape(track.prefix)
          track_path = track_path.gsub(/^#{prefix}/,"")
        end
        puts "Path:    #{track_path}"
        #puts "Played:  #{track.played}"
        #puts "Skipped: #{track.skipped}"
      end
    end

    def adjust_volume(step)
      if(@player == :mplayer)
        mplayer_send_command("volume #{step} 0")
      else
        puts "Adjusting volume is not available for this player..."
      end
    end

    def seek(seconds)
      if(@player == :mplayer)
        mplayer_send_command "seek #{seconds} 0"
      else
        puts "Seeking is not available for this player..."
      end
    end

    # tell player to play
    def play_track
        @playing = true
        # if there isn't a current track yet try to get one
        if(@current_track.nil?)
          advance() 
        end

        file_exists = false
        skip_count = 0
        while not file_exists 
          # make sure that the index is correct
          @current_track_index = 0 if @current_track_index.nil?
          if(@tracks_array[@current_track_index]!=@current_track)
            @current_track_index = @tracks_array.index @current_track
            @current_track_index = 0 if @current_track_index.nil?
          end
          @played_tracks.push(@current_track)
          @current_track_start_time = Time.now
          track_path = @current_track.path
          # use the cached local path if available
          if(@caching && !@current_track.cache_path.nil?)
            track_path = @current_track.cache_path
            puts "Using cache..."
          end
          # either track is a url or it must exist
          file_exists =
            (!((track_path =~ /^http:\/\//).nil?)) || (File.exists?(track_path))


          if not file_exists
            puts "Skipping, #{track_path} does not exist..."
            advance()
            skip_count = skip_count+1
          end

          if skip_count > @tracks_array.length
            puts "All songs skipped... exiting..."
            exit
          end
        end

        current_info
        
        if(@player==:mpg123)
          mpg123_play_track(track_path)
        else
          play_track_thread = Thread.new do 
            print_and_flush "Loading \"#{@current_track.tag[:title]}\"..."
            mplayer_play_track(track_path)
            print_and_flush "\r\e[0K"
          end 
          play_track_thread.priority = 10
        end
        trigger_cache

      end

      # start caching the next songs...
      # given amount of songs to cache ahead, default all
      #def trigger_cache(amount=@tracks_array.length)
      def trigger_cache(amount=1)
        # don't cache if on random play or if can't find current index
        if(@caching and not @random and not @current_track_index.nil?)
          # make the cache directory
          FileUtils.mkdir(@cache_directory) unless 
            File.exists?(@cache_directory)
          # only allow one cache thread to go at once
          @cache_thread.kill unless @cache_thread.nil?
          # handle the cacheing in its own thread since caching is triggered by
          # the player's thread
          @cache_thread = Thread.new{
            # make a local copy of current index to know if we've gone all the
            # way around the list
            index = @current_track_index
            amount.times do
              index = (index +1) % @tracks_array.length
              track = @tracks_array[index]
              # don't recache during this session
              if(track.cache_path.nil? && 
                (track.path =~ /^http:\/\// or @force_caching))
                begin 
                  # for web files
                  if track.path =~ /^http:\/\// 
                    # remove domain name and http junk
                    new_path = File.join(@cache_directory,
                      track.relative_path.gsub(/^http:\/\/[^\/]+\//,""))
                    # assume if file with this name already exists then it IS
                    # the cache of this track
                    if(!File.exists?(new_path))
                      # assumes paths are file system paths not urls
                      http_path = URI.escape(track.path) 
                      # get the contents of the http file
                      contents = open(http_path, 
                        :http_basic_authentication => [@user, @password], 
                        'User-Agent' => 'Ruby-Wget').read 
                      # make sure heirarchy exists for this file
                      FileUtils.mkpath(File.dirname(new_path))
                      # write contents to file
                      File.open(new_path, 'w') {|f| f.write(contents) }
                    end
                  else
                    new_path = File.join(@cache_directory,
                      track.relative_path)
                    # again assume if exists then its the cache
                    if(!File.exists?(new_path))
                      #puts "" if VERBOSE_DEBUG
                      #puts "cp \"#{track.path}\" \"#{new_path}\"" if VERBOSE_DEBUG
                      # make sure heirarchy exists for this file
                      FileUtils.mkpath(File.dirname(new_path))
                      File.copy(track.path, new_path)
                    end
                  end
                  puts ""
                  puts "Successfully cached #{track.path}"
                  # update information in track
                  track.cache_path = new_path
                rescue => ex
                  puts ""
                  puts "Could not successfully cache #{track.path}"
                end
              elsif(track.path =~ /^http:\/\// or @force_caching)
                puts ""
                puts "Already cached #{track.path}"
              end
            end
          }
          @cache_thread.priority=-2
        end
    end

    def down(semaphore)
      while(semaphore<1)
        puts "WAITING ON SEMAPHORE" if VERBOSE_DEBUG
      end
      semaphore -1
    end

    def up(semaphore)
      semaphore + 1
    end
      

    # tell mplayer to play
    def mplayer_play_track(track_path)
      # add password and username to path
      if(!@user.nil? &&  !@password.nil?)
        track_path = track_path.gsub(/^http:\/\//, "http://#{@user}:#{@password}@")
      end

      # Announce new call to this function
      @mplayer_waiting_to_load_path = track_path
      # Wait until others are finished or cancel if not most recent call
      while(@mplayer_loading)
        sleep(0.001)
        if(track_path != @mplayer_waiting_to_load_path)
          return
        end
      end

      # Tell mplayer to load this track
      @mplayer_loading = true
      @mplayer.readall_nonblock
      mplayer_send_command "loadfile \"#{track_path.gsub(/"/,'\"')}\" 0"
      while (line = @mplayer.readline) != "Starting playback...\n"
      end
      @mplayer_loading = false;
    end

    # tell mpg123 to play
    def mpg123_play_track(track_path)
        mpg123_send_command("LOAD "+track_path) 
    end
    
    def advance_and_play_track(amount=1)
      advance(amount)
      play_track
    end
    
    def toggle_pause_import
      @pause_import = !@pause_import;
      if @pause_import
        puts ""
        puts "Importing paused." 
      else
        puts ""
        puts "Importing unpaused."
      end
    end
    
    def pause
      @playing = false
      puts "PAUSED" 
      if(@playing)
        if(@player==:mpg123)
          mpg123_send_pause
        else
          mplayer_send_pause
        end
      end
    end

    def toggle_pause
      @playing = !@playing;
      if not @playing
        print_and_flush "PAUSED" 
      else
        print_and_flush "\r\e[0K"
      end
      if(@playing and @current_track.nil?)
        playing = false
        play_track
      else
        if(@player==:mpg123)
          mpg123_send_pause
        else
          mplayer_send_pause
        end
      end
      # always unset paused_on_mute, actual pause on mute will set this after
      # toggling
      @paused_on_mute = false
    end

    # Pause mpg123 player
    def mpg123_send_pause
      mpg123_send_command("PAUSE")
    end

    # pause mplayer player
    def mplayer_send_pause
      mplayer_send_command("PAUSE")
    end
    
    def reverse_and_play_track(amount=1)
      reverse(amount)
      play_track
    end
    
    def pop_track_off_played_tracks_to_current_track
      @current_track = @played_tracks.pop
      @current_track_index = @tracks_array.index @current_track.path if 
        !@current_track.nil?
    end
    
    # set @current_track to last track played if exists and if current track has
    # been playing for more than 5.0 seconds
    def reverse(amount=1)
      if(not  @played_tracks.nil? and not @played_tracks.empty?)
        # go back to the beginning of current song
        amount.times do
          pop_track_off_played_tracks_to_current_track
        end
        if(Time.now-@current_track_start_time<5.0)
          # extra pop if at beginning of song to actaully go back to the previous
          # track
          if(not  @played_tracks.nil? and not @played_tracks.empty?)
            pop_track_off_played_tracks_to_current_track
          end
        end
      end
    end

    def jump_to_top_of_playlist
      puts "Jumping to top of playlist..."
      puts ""
      @current_track_index = 0
      @current_track = @tracks_array[@current_track_index]
      play_track
    end
    
    # set @current_track to next track
    def advance(amount=1)
      if(@random)
        @current_track_index = rand(@tracks_array.length)
      # just set playlist to the beginning if the current index or current track
      # is not defined
      elsif(@current_track.nil? or @current_track_index.nil?)
        @current_track_index = 0
      else
        @current_track_index  =@current_track_index + amount 
      end
      if @current_track_index>=@tracks_array.length
        if @loop_playlist 
          # if repeating playlist and shuffled then reshuffle
          if(@shuffled and @current_track_index+1>=@tracks_array.length)
            shuffle_tracks_array
            @current_track_index = 0
          else
            @current_track_index% @tracks_array.length 
          end
        # if not looping then just quit
        else
          exit
        end
      end
      @current_track = @tracks_array[@current_track_index]
    end

    # Imports a playlist given a list of track paths. Opens the files using
    # mp3info and finds id3 tag info. Can be paused using pause_import 
    # command.
    # 
    # this is destructive to: @tracks_array
    #   @original_tracks_array
    def import_playlist(lines)
      # resest the original playlist
      @original_tracks_array ||= []
      @tracks_array ||= []
      #bad_files = []
      lines.each do |line|
        while(@pause_import)
          sleep(1)
        end
        Thread.pass
        import_track(line)
      end
      #if(not bad_files.empty?)
      #  puts ""
      #  puts "= Import finished with bad files ="
      #  bad_files.each{|bf| puts bf}
      #  puts ""
      #end
    end


    # return an array of all available mp3 files in given directory
    # optionall recursive, paths are relative to given root
    def find_tracks(root, recursive=false)
      if(recursive)
        paths = `find "#{root}" -name "*.mp3"`.split("\n").collect do |file| 
          file.gsub(/^#{Regexp.escape(root)}/,"")
        end
        return paths
      end
      track_paths = []
      directories = []
      # blank entry for root
      directories << "" 
      directories.each do |dir|
        Dir.new(File.join(root,dir)).entries.each do |subpath|
          if(subpath != "." and subpath != "..")
            path = File.join(dir,subpath)
            path = subpath if dir=="" # special case
            # is a valid directory?
            if(FileTest.directory?(path) and File.readable?(path) and
              not FileTest.symlink?(path))
              # add directory to queue
              directories << path if recursive
            elsif (path =~ /\.mp3$/)
              track_paths<< path
            end
          end
        end
      end
      return track_paths
    end
    
    # Given a list of track paths return the removal of all those
    # that are not already contained in the working playlist
    def remove_already_existing(track_paths,root)
      puts "Trying to remove..."
      begin
        hash = 
          track_paths.inject({}) do |hash, path| 
            hash[File.expand_path(root+path)]=path
            hash
          end
      rescue => ex
        puts ex
      end
      timestamp
      puts "Hash built..."
       
      original_abs_paths =
        @original_tracks_array.collect{|track| File.expand_path(track.path)}
      timestamp
      puts "Collected original tracks..."

      diff = hash.keys - original_abs_paths
      timestamp
      puts "Found difference..."
      
      relative = diff.collect{|abs| hash[abs]}
      timestamp
      puts "Retrieved relative paths"
      return relative
    end
    
    def timestamp
      puts Time.now
    end

    # import all mp3 files in the given directory, optionally recursive
    def import_directory(root, recursive=false, only_new=false)
      # assume recursion and start a queue of nodes
      track_paths = find_tracks(root, recursive)
      puts "Found #{track_paths.length} total tracks..."
      if only_new
        track_paths = remove_already_existing(track_paths,root)
      end
      puts "Found #{track_paths.length} new tracks..."
      track_paths.each do |relative_path| 
        import_track_with_root_and_weight(relative_path, root, 1)
      end
      puts "All tracks in #{root} "+
        "#{recursive ? "and subdirectories " :""}imported."
    end
    
    def import_track(line, quiet=true)
      if(line=~/^(.*?\.mp3)\s*(\s(\d\.\d+))?$/)
        import_track_with_root_and_weight($1, nil,
          ($3.nil? || $3=="") ? 1 : $3, quiet)
      else
        puts "Could not import #{line}... Not proper form..."
      end
    end

    # Takes a line: path/to/track.mp3 1.0
    # with path to file and optional weight and adds the track to the working
    # playlist.
    # destructive to @original_tracks_array
    #                @tracks_array
    def import_track_with_root_and_weight(relative_path,root,weight, quiet=true)
        track = Track.new
        track.relative_path = relative_path 
        track.root_dir = root
        track.weight = weight
        track.played = 0
        track.skipped = 0
        track.tag = {}
        # if path is url than don't try to get tag info
        if track.path =~ /^http:\/\//
        else
          begin
            Mp3Info.open(track.path) do |mp3info|
              track.tag[:artist] = mp3info.tag.artist
              track.tag[:title] = mp3info.tag.title
              track.tag[:album] = mp3info.tag.album
              track.tag[:genre] = mp3info.tag.genre
              track.tag[:year] = mp3info.tag.year
              track.tag[:comment] = mp3info.tag.comment
              # for id3v2 tags
              track.tag[:artist] = mp3info.tag2["TP1"] if(track.tag[:artist].nil?)
              track.tag[:title] = mp3info.tag2["TT2"] if(track.tag[:title].nil?)
              track.tag[:album] = mp3info.tag2["TAL"] if(track.tag[:album].nil?)
              track.tag[:year] = mp3info.tag2["TYE"] if(track.tag[:year].nil?)
            end
          rescue Mp3InfoError
            puts "Bad mp3info found in #{track.path}... skipping info for this file..." 
        #    bad_files << track.path
          rescue Mp3InfoInternalError
            puts "Bad mp3info found in #{track.path}... skipping info for this file..." 
        #    bad_files << track.path
          rescue => ex
            puts "Bad mp3info found in #{track.path}... skipping info for this file..." 
            puts "#{ex.class}: #{ex.message}"
            puts ex.backtrace
        #    bad_files << track.path
          end
        end
        @original_tracks_array << track
        if(@using_originals)
          @tracks_array << track
        end
        if(!quiet)
          puts "#{track.path} imported."
        end
       
    end

    # Use libxml to read and parse an xml playlist
    #   overwrite  whether to overwrite with updated play counts etc
    def load_xml_playlist(xml_file_name,overwrite=false)
      if overwrite
        @xml_file_name = xml_file_name
      end
      @tracks_array ||= []
      @original_tracks_array ||= []
      parser = LibXML::XML::Parser.file(xml_file_name)
      doc = parser.parse
      # check root_dir against current dir?
      
      root_dir = doc.root.attributes["root_dir"] 
      absolute_path_to_playlist_dir = File.expand_path(File.dirname(xml_file_name))
      
      # extract all of the tracks and their info
      doc.root.find("track").each do |track_element|
        # invoke thread schedule to pass execution to other threads
        if(!@readline_thread.nil? && @readline_thread.alive?)
          @readline_thread.join(0.001) 
        end
        #sleep(0.1) while(@pause_import)
        track = Track.new
        # adjust path to be relative to given root_dir
        track.relative_path = track_element.find_first("path").content

        # absolute path to playlist directory
        track.absolute_path_to_playlist_dir = absolute_path_to_playlist_dir

        # only use this track's root dir if given otherwise use global root
        root_dir_object = track_element.find_first("root_dir")
        if(root_dir_object.nil?)
          track.root_dir = root_dir 
        else
          track.root_dir = root_dir_object.content
        end
        if !track_element.find_first("weight").nil?
          track.weight = track_element.find_first("weight").content.to_f
        end
        if !track_element.find_first("played").nil?
          track.played = track_element.find_first("played").content.to_i
        end
        if !track_element.find_first("skipped").nil?
          track.skipped = track_element.find_first("skipped").content.to_i
        end
        track.tag = {}
        tag_element = track_element.find_first("tag")
        Track::TAG_KEYS.each do |key|
          keyed_element = tag_element.find_first(key)
          if(not keyed_element.nil?)
            track.tag[key.intern] = keyed_element.content
          end
        end
        @original_tracks_array << track
        @tracks_array << track if(@using_originals)
      end
    end


    # find the best (most frequent) root_dir
    # could be nil
    def best_root_dir
      hash = {}
      @tracks_array.each do |track|
        if hash.has_key? track.root_dir
          hash[track.root_dir]= hash[track.root_dir]+1 
        else
          hash[track.root_dir] = 1
        end
      end
      best_root = nil
      best_frequency = 0
      hash.keys.each do |key|
        if hash[key] > best_frequency
          best_frequency = hash[key]
          best_root = key
        end
      end
      return best_root
    end

    def write_tracks_array_to_xml_file(tracks_array, xml_file_name)
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct!
      #puts "About to call best_root_dir..."
      root_dir = best_root_dir
      xml.playlist("root_dir"=>root_dir){
        tracks_array.each do |track|
          xml.track{
            xml.path(track.relative_path)
            # only add root dir field if different than global
            xml.root_dir(track.root_dir) unless track.root_dir == root_dir
            xml.weight(track.weight)
            xml.played(track.played)
            xml.skipped(track.skipped)
            if not track.tag.nil?
              xml.tag{
                Track::TAG_KEYS.each do |key|
                  if not track.tag[key.intern].nil?
                    xml.tag!(key, track.tag[key.intern] )
                  end
                end
              }
            end
          }
        end
      }
      xml_file = File.open(xml_file_name,'w') 
      xml_file.write(xml.target!)
      xml_file.close
      puts "Playlist written to #{xml_file_name}."
    end


    # send a command string to mplayer
    def mplayer_send_command(command) 
      @mplayer.puts(command)
      #@mplayer.flush()
    end
    
    # send a command string to mpg123
    def mpg123_send_command(command) 
      @mpg123.write(command+"\n")
      @mpg123.flush()
    end
            
    def puts object
      print_and_flush "#{object}\r\n"
    end

    def print_and_flush object
      print "#{object}"
      $stdout.flush()
    end

    def on_track_finished
      puts "on_track_finished" if VERBOSE_DEBUG
      # finished playing track, increase play count
      @current_track.played = @current_track.played + 1
      append_track_stats(true)
      # This isn't keeping track of play counts so it's just wasting
      # CPU/battery after every song.
      ## write to xml file
      #if not @xml_file_name.nil?
      #  puts "about to start new thread"
      #  xml_thread = Thread.new{
      #    sleep(4)
      #    write_tracks_array_to_xml_file(
      #      @original_tracks_array.clone,@xml_file_name)
      #  }
      #  xml_thread.priority = -10
      #else
      #  puts "xml_file_name was nil"
      #end
    end

    def append_track_stats(played)
      puts "append_track_stats" if VERBOSE_DEBUG
      stat_filename = @xml_file_name.sub(/xml$/,"csv")
      stat = "#{played ? 1 : -1},\"#{@current_track.path}\",#{Time.now.utc.iso8601}\n"
      open(stat_filename, 'a') { |f| f<<stat}
    end
    
  end
end

__END__

TODO:

Time elapsed
Time left
Duration of song
