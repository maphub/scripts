#!/usr/bin/env ruby
# Name          mapdownload.rb
# Description   Downloads the XML map data from a specified host
# Author        Werner Robitza
# Date          Oct-27-2010
# Version       0.2

require 'optparse'
require 'open-uri'
require 'uri'
require 'rexml/document'
require 'ostruct'
require 'pp'
include REXML

# =========================================================================
# Parses the response and looks for a resumption token
#
class ResumptionTokenAnalyzer
  def self.analyze(response)
    
    # Information about the current resumption token status
    resumption = OpenStruct.new
    resumption.available = false
    resumption.token = String.new
    resumption.expires = String.new
    resumption.completeListSize = "0"
    resumption.cursor = "0"
    
    xml = Document.new(response)
    resumptionToken = XPath.first(xml, "//resumptionToken/text()")
    resumption.cursor = XPath.first(xml, "string(//resumptionToken/@cursor)")

    # only if we actually acquired a resumption token
    if !resumptionToken.nil? and !resumptionToken.empty?
      resumption.available = true
      resumption.token = resumptionToken.to_s
      resumption.expires = XPath.first(xml, "string(//resumptionToken/@expires)")
      resumption.completeListSize = XPath.first(xml, "string(//resumptionToken/@completeListSize)")
      # resumption.cursor = XPath.first(xml, "string(//resumptionToken/@cursor)")
    end

    resumption    
  end # self.analyze()
end # class ResumptionTokenAnalyzer

# =========================================================================
# Parses the command line options
#
class OptionParser
  def self.parse(args)
    
    # Collect option values here
    options = OpenStruct.new
    options.set = String.new      # The set to be queried (e.g. gmd)
    options.host = String.new     # The host of the query
    options.format = "mods"       # The metadata format (defualt:. mods)
    options.verb = "ListRecords"  # The default verb to be used
    options.output = "download"       # The default output name
    options.resume = String.new   # Resume at this token if necessary
    
    opts = OptionParser.new do |opts|
      opts.banner = "Usage: mapdownload.rb [options]"
      opts.separator ""
            
      # Mandatory argument: Set
      opts.on("-s", "--set SET", "Use this SET in the query") do |set|
        options.set << set
      end

      # Mandatory argument: Host
      opts.on("-u", "--url URL", "Download the map from this URL", "The request parameters will be appended to this URL.") do |host|
        options.host << host
      end
      
      opts.separator ""
      opts.separator "Optional arguments:"

      # Optional argument: Format
      opts.on("-f", "--format FORMAT", "Download the map using this FORMAT. Default is 'mods'.") do |format|
        options.format = format
      end      
      
      # Optional argument: Output file
      opts.on("-o", "--output OUTPUT", "Use the OUTPUT prefix for all downloaded files. Default is 'download'.") do |output|
        options.output = output
      end
      
      # Optional argument: Resume
      opts.on("-r", "--resume TOKEN", "Use this TOKEN in a request to resume downloading.", "Only use alphanumeric characters!") do |resume|
        options.resume = resume
      end   

      # Optional argument: Verb
      opts.on("-v", "--verb VERB", "Use this VERB in the request. Default is 'ListRecords'.") do |verb|
        options.verb << verb
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
# Issue the first request

# If we start a new download
if options.resume.empty?
  request = String.new
  request = options.host + "?" + "verb=" + options.verb + "&set=" + options.set + "&metadataPrefix=" + options.format
  puts "Sending first request:\t" + request
# if we want to continue from a resumption token
else
  puts "Resuming from token:\t" + options.resume
  request = options.host + "?" + "verb=" + options.verb + "&resumptionToken=" + options.resume  
end

puts "Downloading XML file..."
response = URI.parse(request).read
resumption = ResumptionTokenAnalyzer.analyze(response)
  
outputFileName = options.output + "_" + resumption.cursor + ".xml"
output = File.new(outputFileName, "w")
output.write(response)
output.close
  
puts "Finished downloading"

# =========================================================================
# Issue all other requests if there was a resumption token

while resumption.available
  puts "Resumption token found:\t" + resumption.token
  puts "Cursor at " + resumption.cursor + " of " + resumption.completeListSize
  
  request = options.host + "?" + "verb=" + options.verb + "&resumptionToken=" + resumption.token
  puts "Sending next request:\t" + request
  puts "Downloading XML file..."
  response = URI.parse(request).read  
  resumption = ResumptionTokenAnalyzer.analyze(response)

  outputFileName = options.output + "_" + resumption.cursor + ".xml"  
  output = File.new(outputFileName, "w")
  output.write(response)
  output.close

  puts "Finished downloading"
end

puts "Finished downloading all files"
exit
