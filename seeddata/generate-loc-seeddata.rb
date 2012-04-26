#!/usr/bin/env ruby
# Name          generate-loc-seeddata.rb
# Description   Generates yaml file with selected metadata from a directory of metadata (*.xml) and directory of maps (images.jp2)
# Author        Shion Guha
# Date          April 26, 2012 (last modified)

#require + libraries section
require 'optparse'
require 'ostruct'
require 'rexml/document'
require 'yaml'

include REXML
include YAML

#Getting commandline arguments and putting them in new strings
# The correct way to using this script "ruby generate-loc-seeddata.rb mapimgdir metadatadir numberofsamples"
# An example of the above is "ruby generate-loc-seeddata.rb maps metadatas 30"
# Writing and modifying class optionparser borrowed from maphub/fetch_metadata.rb

# Parses the command line options
class OptionParser
  def self.parse(args)
    
    # Collect option values here
    options = OpenStruct.new
    options.mapimgdir = String.new     # The map image directory to be parsed.
    options.metadata = String.new  # The metadata directory to be parsed.
    options.num	 = String.new       # The default number of samples in the yaml file
    
    opts = OptionParser.new do |opts|
      opts.banner = "Usage: generate-loc-seeddata.rb [options]"
      opts.separator ""
      
      opts.separator "Mandatory Arguments:"

      # Mandatory Argument: MapImgDir directory
      opts.on("-i", "--mapimgdir MAPIMGDIR", "Parse this MAPIMGDIR to get identifiers.") do |mapimgdir|
        options.mapimgdir = mapimgdir
      end      
      
      # Mandatory argument: Metadata directory
      opts.on("-m", "--metadata METADATA", "Parse this METADATADIR to build output YAML file.") do |metadata|
        options.metadata = metadata
      end 

      # Mandatory argument: Number of samples
      opts.on("-n", "--num NUM", "Use this NUM of samples.") do |num|
        options.num = num
      end      

      opts.separator ""
      opts.separator "Common options:"
      
      # Show help message
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
      
    end # opts

    opts.parse!{args}
    options

  end # self.parse()
end # class OptionParser

# =========================================================================
# Parse the options

options = OptionParser.parse(ARGV)


# =========================================================================
#Section which takes the parsed option variables and stores them in my own
mapsimgdir = options.mapimgdir
metadatadir = options.metadata
numsamples = options.num.to_i

# 1. Iterate over all files in the given directory. Grab file names -.*.mm2
# and store them in some data structure. Grabs only numsamples number of filenames

#getting basedirectory
mapdir = Dir.pwd + "/" + mapsimgdir

#getting contents of the mapdir, removing extension, printing eachfilename
mapfilenames = Dir.glob(File.join(mapdir, '*.jp2'))
basefile = Array.new()
maplength = mapfilenames.length
counter = 0	

puts "Finding all the map files..."
#doing some fancy manipulations to get an array of id names.
for file in mapfilenames
	eachmapfile = File.basename(file,".jp2")
	if counter <= maplength - 1
		basefile.insert(counter,eachmapfile)
		counter = counter +=1
	else
	end
end
puts "Done !"

puts "Finding all the metadata files ..."
# 2. Iterate within each file in a given directory and match previous filenames
# stored in data structure with individual metadata record.
metadir = Dir.pwd + "/" + metadatadir

#setting up the metadata directory to access every file
metafilenames = Dir.glob(File.join(metadir, '*.xml')) 
metarray = Array.new()
metalength = metafilenames.length
counter1 = 0

#iterating through each metadata file and getting an array of all metadata filenames
for file1 in metafilenames
	eachmetafile = File.basename(file1)
	if counter1 <= metalength - 1
		metarray.insert(counter1,eachmetafile)
		counter1 = counter1 +=1
	else
	end
end

#able to get final array of all metadata files ! Success !
puts "Done !"

# 3. Build YAML file based on given structure from matched map filename
# and metadata.

#puts xmldoc
#Success in reading particular elements. Now, lets see if the mapids can be matched.
i = 0
j = 0
k = 1
metlength = metarray.length - 1
puts "Creating output YAML File"

#Trying out method with file.open
File.open("loc-seeddata.yaml","w") do |f|
	#iterating over all metadata files
	metarray.each{|m| 
	
		#Building xml document for current metadata file
		xmlfile = File.new(metadir +"/" + m)
		xmldoc = Document.new(xmlfile)
	    idregex = %r|oai:lcoa1.loc.gov:loc.gmd/|
	    #baseid = "oai:lcoa1.loc.gov:loc.gmd"
		curids = Array.new()
		$arrayid = Array.new()
		counter2 = 0
		
		#Getting an array of identifier nodes by regexing from the full xmldoc
		identifier_nodes = XPath.each(xmldoc, "//identifier") {|element| 
				if element.text=~idregex
					curids.insert(counter2,element)
					counter2 +=1
				end	
		}
		#iterating over ids
		for ids in curids
			
			#Getting the <record> tag level
			record_node = ids.first.parent.parent.parent
						
			#processing identifier
			$idstr = ids.to_s
			$arrayid = $idstr.split(%r{\/})
			id = $arrayid[1].delete("<")
					
							
			#Creating yaml file structures
			begin
				titleelement = record_node.elements['metadata/mods/titleInfo/title'].text 
			rescue
				titleelement = nil
				puts "Title not found in record ..."
			end
			#getting author
			begin
				nameelement = record_node.elements['metadata/mods/name/namePart'].text
			rescue
				nameelement = nil
				puts "Author name not found in record ..."
			end
			#getting date
			begin
				dateelement = record_node.elements['metadata/mods/originInfo/dateIssued'].text
			rescue
				dateelement = nil
				puts "Date Issued not found in record ..."
			end
			#getting subject with authority lcsh
			begin
				subjectelement = record_node.elements['metadata/mods/subject[@authority="lcsh"]/topic'].text
			rescue
				subjectelement = nil
				puts "Subject tags from LCSH not found in record..."
			end
			#Building yaml structure
			sampleyaml = {"map" => k, "id" => id, "title" => titleelement, "author" => nameelement, "subject" => subjectelement, "date" => dateelement}
			#writing to file
			#puts "Writing record to output file..."
			f.write(sampleyaml.to_yaml)
			
			print "Writing " + k.to_s + " of " + numsamples.to_s + " records...\n"
			#STDOUT.flush
			
			k +=1
			#checking k against numsamples and exiting if numsamples reached.
			
			if k > numsamples
				puts "All Done !"
				Process.exit
			end
			
		end
	} # end metadata
	#puts "done with metadata"
end
#puts "done with file"
