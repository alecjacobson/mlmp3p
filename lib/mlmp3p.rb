#!/opt/local/bin/ruby -w
#!/usr/local/bin/ruby -w
# mlmp3p
# Version: 0.02
# Author: Alec Jacobson (alecjacobson@nyu.edu)
#

# make sure this development folder is in load path
# this is need for easy developement and debugging I don't think it is
# harmfully to distribute, but probably should remove or hid 
$LOAD_PATH << File.expand_path(File.dirname($0))

require 'controller'
require 'player'
