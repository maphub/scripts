# TODO: keep the intro short (e.g., https://github.com/maphub/maphub-seeddata/blob/master/scripts/imagedownload.rb)

# Production script for maphub. Script description as follows:
# We need a script that generates a seed data file for the Library of Congress Maphub instance.
# Each "map record" in the seed data file includes:
# - pointers to the map image file URIs
# - selected metadata fields (title, description, subject, creator)
# 
# We already have the maps in place and scripts to download metadata from the LoC's GMD collection (see scripts directory). The script has to read these map identifiers, iterate over the harvested metadata records, identify matching records (based on the map identifier), and output a maphub map record for each match.
# The challenging part of this script is to select the appropriate metadata fields from the OAI-PMH records. We want only those that carry "relevant" semantics about the map. Also some data cleansing (whitespace, special chars, etc.) steps might be necessary. At the end the metadata need to be indexed by Apache Solr / Lucene.
# The results should be a script generate-loc-seeddata which takes the directory of map image files and a directory of XML files (= the metadata records) and a set of identifiers (probably a TXT file) as input and generates an outputfile loc-seeddata.yaml
# 
# Possible execution:
# generate-loc-seeddata maps/ metadata/*.xml
# generate-loc-seeddata -n 10 maps/ metadata/*.xml for only 10 maps
# Script Development: April 2012 by Shion Guha, Cornell University (as part of maphub project led by Dr. Bernhard Haslhofer)
# Last Change: April 8, 2012

#Setting up practice space for passing parameters {mapimgdir, metadatadir, numberofsamples}
# Algorithm:
# 1. Parameters are passed into the script
# 2. An array of identifiers are built as per {numberofsamples} from the {imagedir}
# 3. Looping {numberofsamples} times:
# 4. The correct metadata file from {metadatadir} is identified with the current identifier.
# 5. The metadata XML is parsed and the needed information {identifier,title,author,subject,date} is extracted.
# 6. The output YAML file is appended with the information in the proper format.

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
numsamples1 = numsamples - 1 #TODO: do you really need two vars here?

# 1. Iterate over all files in the given directory. Grab file names -.*.mm2
# and store them in some data structure. Grabs only numsamples number of filenames

#getting basedirectory
mapdir = Dir.pwd + "/" + mapsimgdir # TODO: don't assume that the maps dir is always a subdir of the current dir

# TODO: why not simply list all files in the dir and add them to an array?

#getting contents of the mapdir, removing extension, printing eachfilename
mapfilenames = Dir.glob(File.join(mapdir, '*.jp2'))
basefile = Array.new()
maplength = mapfilenames.length
counter = 0	# TODO: you don't need a counter; you have the array

puts "Finding all the map files..."
#doing some fancy manipulations to get an array of id names.
for file in mapfilenames
	eachmapfile = File.basename(file,".jp2")
	if counter <= maplength - 1
		basefile.insert(counter,eachmapfile)
		counter = counter + 1
	else
	end
end

#able to get final array of map names without extension. Success !
# puts basefile[10]
# puts basefile[11]
# return

puts "Finding all the metadata files ..."

# TODO: what about writing a function that stores all filenames in array?
# Avoid duplicated code

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
		counter1 = counter1 + 1
	else
	end
end

#able to get final array of all metadata files ! Success !
#puts metarray

# 3. Build YAML file based on given structure from matched map filename
# and metadata.

#puts xmldoc
#Success in reading particular elements. Now, lets see if the mapids can be matched.
i = 0
j = 0
metlength = metarray.length - 1
puts "Creating output YAML File"
#Firstly, looping over numsamples - 1 :: i.e. for every sample requested.

# TODO: avoid excessive IO -> in the worst case you are opening and closing the
# output file (no_metadata_records * no_maps) times

# TODO: simply open the output file and the then within the block, iterate over
# all metadata xml files; in each metadata xml file, iterate over all records;
# if a record identifes an item that is in the list of known map file names,
# extract the defined record fields and write them to the output file.

while j <= metlength
	while i <= numsamples1
		k = i + 1
		# Trying to match mapids
		#Stupid preceding string in the <identifier> tag and building full identifier thingy
		baseid = "oai:lcoa1.loc.gov:loc.gmd/"
		mapid = basefile[i]
		fullid = baseid + mapid
		#puts "This is the image id number: " + i.to_s() + " and its id is " + fullid #Success in looping over all ids.
		#Opening current metadatafile with xml stuff
		xmlfile = File.new(metadir + "/" + metarray[j] )
		xmldoc = Document.new(xmlfile)
		#puts "The current metadata file being parsed is: " + metarray[j] #Success ! Now, need to parse every unique xml file and build yaml stuff.
		identifier_nodes = XPath.match(xmldoc, "//identifier[text()='oai:lcoa1.loc.gov:loc.gmd/"+mapid+"']")
		#puts identifier_nodes
		record_node = identifier_nodes.first.parent.parent
		#puts record_node Success !
		#Now to get everything else.
		begin
			titleelement = record_node.elements['metadata/mods/titleInfo/title'].text #Success ! Getting title works.
		rescue
			titleelement = nil
			puts "Title not found in record ..."
		end
		# getting author
		begin
			nameelement = record_node.elements['metadata/mods/name/namePart'].text
		rescue
			nameelement = nil
			puts "Author name not found in record ..."
		end
		# getting date
		begin
			dateelement = record_node.elements['metadata/mods/originInfo/dateIssued'].text
		rescue
			dateelement = nil
			puts "Date Issued not found in record ..."
		end
		# getting subject with authority lcsh
		begin
			subjectelement = record_node.elements['metadata/mods/subject[@authority="lcsh"]/topic'].text
		rescue
			subjectelement = nil
			puts "Subject tags from LCSH not found in record..."
		end
		sampleyaml = {"map" => k, "id" => mapid, "title" => titleelement, "author" => nameelement, "subject" => subjectelement, "date" => dateelement}
		File.open('loc-seeddata.yaml',"a") {|f| f.write(sampleyaml.to_yaml)} #Success ! YAML file built
		puts "Writing sample no: " + k.to_s() + " and its selected metadata to the output YAML file ..."
		i+= 1
	end
j+=1
end