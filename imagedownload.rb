#!/usr/bin/env ruby
# Name          imagedownload.rb
# Description   Downloads the images corresponding to data downloaded by
#               the mapdownload script
# Author        Werner Robitza
# Date          Nov-11-2010
# Version       0.2

require 'optparse'
require 'open-uri'
require 'uri'
require 'rexml/document'
require 'ostruct'
require 'pp'
include REXML


# =========================================================================
# Writes a log file for all images found or not found
class Logger
  
  # Initialize output file
  def initialize(output)
    time = Time.new
    @filename = 
      "log_" + 
      time.year.to_s + "_" + 
      time.month.to_s + "_" + 
      time.day.to_s + "_" + 
      time.hour.to_s + 
      time.min.to_s + 
      ".txt"
    @filename = File.join(output, @filename)
  end
  
  # Log to the file
  def log(folder, id, url, found)
    @file = File.new(@filename, "a")
    string = 
      folder + "\t" +
      id + "\t" + 
      url + "\t" + 
      found.to_s + "\n"
    @file.write(string)
    @file.close
  end
end

# =========================================================================
# Parses the command line options
#
class OptionParser
  def self.parse(args)
    
    # Collect option values here
    options = OpenStruct.new
    options.output = "."     # The output folder
    options.log = false             # If a log file should be written
    options.time = 0                # The time interval between downloading images
    options.host = "http://memory.loc.gov"  # The host do download from
    options.format = "gif"          # The image format to be downloaded
    
    opts = OptionParser.new do |opts|
      opts.banner = "Usage: imagedownload.rb [options]"
      opts.separator ""
            
      # Mandatory argument: File
      opts.on("-i", Array, "Use these FILES as input") do |input|
        options.input = input # TODO - does not work?
      end

      # Mandatory argument: File
      opts.on("-o", "--output OUTPUT", "Use this OUTPUT directory to save the images") do |output|
        options.output = output
      end

      opts.separator ""
      opts.separator "Optional arguments:"

      opts.on("-f", "--format FORMAT", "Use this FORMAT as the default images to be downloaded. Default is 'gif'") do |format|
        options.format = format
      end

      opts.on("-l", "--log", "Write a log file to the output directory") do |log|
        options.log = log
      end

      opts.on("-t", "--time TIME", "Use this TIME interval in seconds to throttle downloading between each image") do |time|
        options.time = time.to_i
      end      
      
      opts.on("-u", "--url URL", "Use this URL as the base to search for images") do |host|
        options.host << host
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
# Create the output and log
if !File.directory? options.output
  Dir.mkdir(options.output)
end


logger = Logger.new(options.output) if options.log


# =========================================================================
# Read from the files

ARGV.each do |input|

  # Check if the file exists
  if File.exists?(input)
    puts "INFO:\tOpening file:\t" + input
    document = File.read(input)
    xml = Document.new(document)
    
    identifierTotal = XPath.first(xml, "count(//header/identifier)").to_s
    identifierCurrent = 0
    puts "INFO:\tStarting download of " + identifierTotal + " files" 
    
    use_alternative = false
    
    XPath.each(xml, "//header/identifier") do |identifier|
      begin
        identifierCurrent += 1 if !use_alternative
        
        # Construct the image properties from the identifier
        # This is highly specific to the data stored and should be changed if necessary
        # EXAMPLE IDENTIFIER: oai:lcoa1.loc.gov:loc.gmd/g9160s.ct001196
        image = OpenStruct.new
        
        # get the the set identifier, e.g. gmd
        image.set = identifier.text.split("/")[0].split(".")[3]

        # get the the subset, e.g. gmd9
        image.subset = image.set + identifier.text.split("/")[1].split(".")[0].match(/\d/)[0]

        # get the alternative subset, e.g. gmd916, this applies to some records
        image.subset_extended = image.set + identifier.text.split("/")[1].split(".")[0].match(/\d{3}/)[0]

        # get the full folder name (e.g. g1234 or g9160s)
        image.folder = identifier.text.split("/")[1].split(".")[0] 

        # the simple folder name is the same as the full (e.g. g1234)
        image.folderSimple = image.folder
        
        # get the ID of the image (e.g. ct001196)
        image.id = identifier.text.split("/")[1].split(".")[1]
        
        # also get an other simple representation for the folder 
        # but only if it had a character at the end (e.g. g9160s -> g9160)
        testMatchSimple = image.folder.match(/\w{1,2}\d{4}/) # only get the simple parts
        if testMatchSimple != nil
          testMatchSimple = testMatchSimple[0]
          image.folderSimple = testMatchSimple if testMatchSimple != image.folder
        end
        
        # if the folder looks something like g9160sm
        testMatchExtended = image.folder.match(/[a-z]{2}$/)
        if testMatchExtended != nil
          # the subset is different (gmd9 -> gmd9m)
          image.subset = image.subset + image.folder.match(/[a-z]{1}$/)[0]
          # the simple folder is also different (g9160 -> g9150m)
          image.folderSimple = image.folderSimple + image.folder.match(/[a-z]{1}$/)[0]
        end

        
        # compose the request
        request = 
          options.host + "/" +          # http://memory.loc.gov/
          image.set + "/" +             # gmd
          image.subset + "/" +          # gmd9, gmd9m
          image.folderSimple + "/" +    # g9160s, g9160m (if it was g9160sm)
          image.folder + "/" +          # g9160s
          image.id + "." +              # ct001196
          options.format
        
        # compose an alternative request
        request_alt = 
          options.host + "/" +          # http://memory.loc.gov/
          image.set + "/" +             # gmd
          image.subset_extended + "/" + # gmd916
          image.folderSimple + "/" +    # gmd9160
          image.folder + "/" +          # gmd9160s
          image.id + "." +              # ct001196
          options.format
        
        # open the output folder and write to that
        outputFileName = image.folder + "." + image.id + "." + options.format  
        outputFileName = File.join(options.output, outputFileName)
        
        if File.exists?(outputFileName)
          puts "WARNING:\tFile " + outputFileName + " already exists. Skipping."
        else
          # downlaod the image
          puts "INFO:\tDownloading image file..."
          if !use_alternative
            puts "INFO:\tSending request:\t" + request
            response = URI.parse(request).read
          else
            puts "INFO:\tSending request:\t" + request_alt
            response = URI.parse(request_alt).read
          end
          
          # write to output file
          output = File.new(outputFileName, "w")
          output.write(response)
          output.close
          puts "INFO:\tFinished downloading image file " + identifierCurrent.to_s + " of " + identifierTotal

          logger.log(image.folder, image.id, request, true) if options.log and use_alternative
          logger.log(image.folder, image.id, request_alt, true) if options.log and !use_alternative
          
          # reset the alt switch
          use_alternative = false
        end
        
        if options.time != 0
          puts "INFO:\tWaiting for " + options.time.to_s + " seconds to download next file..."
          sleep(options.time)
          puts "Done"
        end
        
      # catch a 404 exception
      rescue OpenURI::HTTPError => e
        puts "ERROR:\t" + image.id + " was not found (404)"
        # if we have not used the alternative link yet
        if !use_alternative
          puts "INFO:\tTrying alternative URL."
          use_alternative = true
          retry
        end
        # if we already used the alternative, log and go to next image
        logger.log(image.folder, image.id, request, false) if options.log
      
      # catch any other exception
      rescue
        puts "ERROR:\t" + image.id + " could not be downloaded."
        logger.log(image.folder, image.id, request, false) if options.log
      end
      
      
    end # XPath each
  else
    puts "ERROR:\tCould not find file:\t" + input
    puts "INFO:\tTrying next file..."
  end # file exists?
  
end # ARGV.each

exit
