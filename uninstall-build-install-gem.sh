echo "sudo gem uninstall mlmp3p"
sudo gem uninstall mlmp3p
echo "gem build mlmp3p.gemspec"
gem build mlmp3p.gemspec 
VERSION=`grep version mlmp3p.gemspec | sed -e "s/.*\([0-9]\.[0-9]*\).*/\1/"`
gem_file="mlmp3p-${VERSION}.gem"
echo "sudo gem install $gem_file"
sudo gem install $gem_file
echo "sudo cp mlmp3p /usr/local/bin/mlmp3p"
sudo cp mlmp3p /usr/local/bin/mlmp3p
echo "sudo cp mlmp3p-playlist /usr/local/bin/mlmp3p-playlist"
sudo cp mlmp3p-playlist /usr/local/bin/mlmp3p-playlist
