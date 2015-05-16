# Master install script
#
#

installer="apt-get install"
installer="port install"
# fink should work too...

function simple_install {
  program_name="$1"
  echo -ne "$program_name... "
  program_name_path=`which $program_name`
  if [ $program_name_path ]; then
    echo "$program_name_path"
  else
    echo "$installer $program_name..."
    sudo $installer $program_name
    program_name_path=`which $program_name`
  fi
}

# ask for mplayer/mpg123/both
r=""
while [ "$r" != "mplayer" -a "$r" != "mpg123" -a "$r" != "both" ]
do
    read -p "Which mp3 player should mlmp3p wrap (mplayer/mpg123/both)?  " r
    echo
done

if [ "$r" == "mplayer" -o "$r" == "both" ]; then
  simple_install "mplayer"
  mplayer_path=$program_name_path
fi

if [ "$r" == "mpg123" -o "$r" == "both" ]; then
  simple_install "mpg123"
  mpg123_path=$program_name_path
fi

# seems as if this might just be easier without the simple_install function...

# force install on mac
simple_install "ruby"
# check that which ruby returns new ruby

simple_install "rb-rubygems"
sudo gem install "ruby-mp3info"
sudo gem install "builder"
# mac
  simple_install "libxml2"
# linux
  simple_install "libxml2-dev"
sudo gem install "libxml-ruby"

