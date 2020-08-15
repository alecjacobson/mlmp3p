#    mlmp3p 
     
      l
      i
      t  m
      t mp
     mlmp3p
     yep3 l
       3  a
          y
          e
          r


My Little MP3 Player
Alec Jacobson
alecjacobson@gmail.com

Play mp3s and manage playlist via the command line with this ruby wrapping for
`mplayer` and `mpg123`

## Prerequisites
    ruby
    rubygems
    mp3info  (gem)
    builder  (gem)
    libxml   (gem+)
    ftools   (gem)
    mplayer or mpg123

## Installation of prerequisites (Mac OS X)
  ** Do NOT use the ruby that came with your mac

  ** You must install a true copy of ruby (either using mac ports or
  ** directly from ruby site)
  
  ** Do NOT use the ruby that came with your mac
  
### Using homebrew

    brew install ruby
    gem install ftools ruby-mp3info builder libxml-ruby 

Install

    sudo gem install mlmp3p-[version].gem
    sudo cp mlmp3p /usr/local/bin/mlmp3p 
    sudo cp mlmp3p-playlist /usr/local/bin/mlmp3p-playlist


## Running mlmp3p

  Play files in a directory

     mlmp3p [path to directory with mp3s]

  Play files from a txt file list of paths

     mlmp3p songs.txt

  Play files from an mlmp3p xml playlist

     mlmp3p songs.xml

  Save songs in a directory to an mlmp3p xml playlist

     mlmp3p-playlist [path to directory with mp3s]

  Save songs in txt file list of paths to an mlmp3p xml playlist

     mlmp3p-playlist songs.txt

## Help / Trouble Shooting

> YET TO IMPLEMENT

To print usage instructions 

     mlmp3p -h

  To print short and long commands help

     mlmp3p -commands

**Useful tip:**
Export a playlist from itunes as `plain-text.txt` then convert to simple list of file paths `playlist.txt` using:

    cat plain-text.txt | tr '\r' '\n' | sed -n "s#.*:Users:\(.*\)#Users:\1#p" | tr ':' '/' >playlist.txt
