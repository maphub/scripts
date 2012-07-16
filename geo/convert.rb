#!/usr/bin/env ruby

require 'date'
require 'fileutils'
require 'getoptlong'
require 'json'
require 'net/http'
require 'rexml/document'
require 'tmpdir'
require 'uri'


#$GDALRoot = '/usr/share/gdal/1.7'
#$GDALRoot = '/usr/local/share/gdal' => OS X
$GDALRoot = '/usr/share/gdal/1.9'
$tilesetName = 'ts_google'


# Create an easy way to test if the specified map ID is an integer.
class String
  def is_int?
    begin
      Integer(self)
      true
    rescue
      false
    end
  end
end



#
# TilesetConverter converts images into tile sets. Amazing!
#
# One can invoke this class in two ways:
#
#   1. From the command line by e.g.: ./convert.rb -m 7 ...
#   2. From another script by including this file and running the main method
#      e.g.: TilesetConverter.new.main({ 'mapID' => 7, ... })
#
# Process parameters are specified either by command-line switches in the first
# case or a Hash passed into the main method in the second case. Valid process
# parameters are:
#
#   sleepDelay (optional, defaults to one hour)
#   mapID (optional)
#   imageDirectory
#   metadataServerURL
#
# This class uses a "checkpoints" file to maintain a list of dates representing
# the last time a map's tile set was generated. The path of this file is defined
# by the @checkpointsFile instance variable. By default this file is located at
# /tmp/maphub-image-conversion-checkpoints. Only upon successful completion of
# the conversion process is the date updated for a map.
#
# When provided a map ID, the process will only attempt to update that map's
# tile sets. When a map ID is not specified, the process will attempt to update
# all maps discovered at the metadata server. An attempt consists of first
# comparing the map's updated_at date to any previous checkpoint, and if the map
# has been updated (or there is no checkpoint for that map), the process then
# looks for the requisite number of control points. If enough control points are
# found, the image generation process is started.
#
# The image generation process creates a number of files, including the tile
# set, first in a temporary directory. After creating the tile set, the current
# tile set (if any) is removed and the new tile set is moved into its place.
#
# If a sleep delay is specified, the process will wait that number of seconds
# and re-process the specified parameters (all the maps or the single map). If
# no delay is specified, processing will halt after the first attempt.
#
class TilesetConverter
  def initialize()
    @checkpointsFile = '/tmp/maphub-image-conversion-checkpoints'
    if (!File.exists?(@checkpointsFile)) then FileUtils.touch(@checkpointsFile) end
    
    file = File.new(@checkpointsFile, 'r')
    rawData = file.read
    file.close
    
    if (rawData.length > 0)
      @checkpoints = JSON.parse(rawData)
    else 
      @checkpoints = []
    end
  end
  
  # Process the images in a loop forever.
  # @throws Exception if the specified parameters are invalid.
  def main(params = nil)
    # Make sure the discovered parameters are valid.
    begin
      # If there are no params passed in, attempt to get them from the CLI.
      if (params == nil) then params = getParameters() end
      
      # Validate the parameters regardless of whence they came.
      validateParameters(params)
    rescue Exception => e
      if (__FILE__ == $0)
        # We are being used via the CLI, show the error and usage output.
        returnCode = usage(e.message())
        exit returnCode
      else
        # We are being used in another application, throw the current
        # exception up another level.
        raise
      end
    end

    # By default, keep processing. This will be prevented if we are only
    # supposed to process once. Otherwise, we will sleep and continue.
    while (true)
      mapID = params.has_key?('mapID') ? params['mapID'] : nil
      
      begin
        # Contact the server and download the metadata for the specified map
        # (or for all maps if one was not specified as a parameter).
        mapList = getMapList(params['metadataServerURL'], mapID)
        puts 'Maps: '+mapList.to_s

        # Process any images identified in the metadata fetched above.
        processedIDs = []
        mapList.each do |metadatum|
          if (processImage(params, metadatum))
            processedIDs.push(metadatum['id'])
          end
        end
      
        # Update the checkpoints file for the maps we were given.
        updateCheckpoints(processedIDs)
      rescue Exception => e
        # The connection to the server timed out. If we're running the loop
        # we should just keep running and attempt again during the next run.
        # Otherwise the script will just exit.
        puts 'Error: '+e.to_s
        raise
      end
      
      # If we were given a sleep delay, wait for that delay and continue
      # processing. If we weren't, stop processing (after what should be a
      # single run).
      if (params.has_key?('sleepDelay'))
        sleep(params['sleepDelay'])
      else
        break
      end
    end
  end
  
  
  
  # Process the specified image if applicable.
  #
  # @param params The application parameters (bleh).
  # @param metadata The overview metadata for the maps to process.
  # @return True if the image was processed, false otherwise.
  def processImage(params, metadata)
    url = params['metadataServerURL']
    
    # This is used to determine if we should actually process this image or
    # not, based on some criteria (e.g. modification date and whether or not
    # the tile set exists.
    process = false
    
    # See if there is an existing checkpoint and date for this map.
    checkpointDate = nil
    @checkpoints.each do |checkpoint|
      if (checkpoint['id'].to_s == metadata['id'].to_s)
        checkpointDate = DateTime.parse(checkpoint['updated_at'])
        break
      end
    end
    
    # If there is no date, then we haven't seen this map before, so we want
    # to process it. Otherwise, we only process the map if the new date is
    # more recent than the old checkpoint date.
    currentDate = DateTime.parse(metadata['updated_at'])
    if (checkpointDate == nil || checkpointDate < currentDate) then process = true end
    
    # We don't want to process an image if there aren't enough control points,
    # regardless of if the times check out...
    if (metadata['no_control_points'].to_i < 3) then process = false end
    controlPoints = fetchControlPoints(url, metadata['id'])

    if (process)
      puts 'Processing map '+metadata['id'].to_s+'...'
      
      # Reset the metadata to include all the in-depth metadata for this map.
      metadata = getMapMetadata(url, metadata['id'])
      fileName = metadata['identifier']
      
      # The y values in the database is "wrong": the conversion commands
      # start from the top left corner but MapHub starts from the bottom
      # left. Therefore, we need to "flip" the y values around the median
      # line of the map.
      mapHeight = Float(metadata['height'])
      median = mapHeight / 2
      controlPoints.map! do |cp|
        y = Float(cp['y'])
        if (y > median)
          difference = y - median
          y = median - difference
        elsif (y < median)
          difference = median - y
          y = median + difference
        else
          # This point is exactly on the median. Don't anger it.
        end
        cp['y'] = y
        cp
      end
      
      ENV['GDAL_DATA'] = $GDALRoot
      dir = Dir.mktmpdir()
      
      # Translate the image.
      translateCommand = 'gdal_translate -of VRT -a_srs EPSG:4326'
      controlPoints.each do |cp|
        translateCommand = translateCommand+' -gcp '+cp['x'].to_s+' '+cp['y'].to_s+' '+cp['lng']+' '+cp['lat']
      end
      translateCommand = translateCommand+' '+params['imageDirectory']+'/raw/'+fileName+'.jp2 '+dir.to_s+'/'+fileName+'-original.vrt'
      puts "Translating: #{translateCommand}"
      system(translateCommand)
      
      # Warp the image.
      warpCommand='gdalwarp -of VRT -s_srs EPSG:4326 -t_srs EPSG:4326 '+dir.to_s+'/'+fileName+'-original.vrt '+dir.to_s+'/'+fileName+'-warped.vrt'
      puts "Warping: #{warpCommand}"
      system(warpCommand)

      # Generate the tile set, placing the generated images in the temporary
      # directory.
      #tileCommand='gdal2tiles.py -n '+dir.to_s+'/'+fileName+'-warped.vrt '+dir.to_s+'/'+$tilesetName
      publishURL = params['publishServerURL'] + $tilesetName + "/" + fileName + ""
      tileCommand='gdal2tiles.py -u '+publishURL+' -k '+dir.to_s+'/'+fileName+'-warped.vrt '+dir.to_s+'/'+$tilesetName
      puts "Tiling: #{tileCommand}"
      system(tileCommand)
      
      # Next we need to tell the server what the new map boundaries are. Get
      # the XML data so we can parse out the boundaries.
      # xmlFile = File.new(dir.to_s+'/'+$tilesetName+'/tilemapresource.xml')
      # xmlDoc = REXML::Document.new(xmlFile)
      # bounds = xmlDoc.root.elements['BoundingBox'].attributes
      #       
      # Make a PUT request to update the map with the new boundaries.
      # This is disabled for the time being.
      # uri = URI(params['metadataServerURL'].to_s+'maps/'+metadata['id'].to_s)
      # request = Net::HTTP::Put.new(uri.path)
      # request.set_form_data(
      #   'ne_lat' => bounds['maxx'],
      #   'ne_lng' => bounds['maxy'],
      #   'sw_lat' => bounds['minx'],
      #   'sw_lng' => bounds['miny']
      # )
      # http = Net::HTTP.new(uri.host, uri.port)
      # response = http.request(request)
      
      # Clean up the generated files to leave only the images and the XML
      # file which contains the map bounds and other GIS information.
      FileUtils.rm(Dir.glob(dir.to_s+'/'+$tilesetName+'/*.html'))
      
      # Remove the current tile set and move the new tile set into its
      # place.
      FileUtils.mkdir_p(params['imageDirectory']+'/'+$tilesetName)
      FileUtils.rm_rf(params['imageDirectory']+'/'+$tilesetName+'/'+fileName)
      FileUtils.mv(dir.to_s+'/'+$tilesetName, params['imageDirectory']+'/'+$tilesetName+'/'+fileName)

      return true
    end
    
    return false
  end
  
  
  
  # Retrieve from the server any existing control points for the specified map.
  def fetchControlPoints(url, mapID)
    url = URI(url.to_s+'maps/'+mapID.to_s+'/control_points.json')
    response = Net::HTTP.get_response(url)
    data = response.body
    JSON.parse(data)
  end
  
  
  
  # This could probably be improved...
  def updateCheckpoints(mapIDs)
    now = DateTime.now.to_s

    # Go through the processed IDs and update them in-place within the
    # checkpoints Array. If the processed ID doesn't exist in the checkpoints
    # Array, append it
    mapIDs.each do |id|
      found = false
      @checkpoints.map! do |checkpoint|
        if (checkpoint['id'] == id)
          found = true
          checkpoint['updated_at'] = now
        end
        checkpoint
      end
      
      if (!found) then @checkpoints.push({ 'id'=>id, 'updated_at' => now}) end
    end

    # Save the new checkpoints to the file
    json = JSON.generate(@checkpoints)
    file = File.new(@checkpointsFile, 'w')
    file.write(json)
    file.close
  end
  
  

  # Retrieve map overview metadata from the server. If no map ID is specified,
  # metadata for all maps is returned. Otherwise, an Array with a single entry
  # containing the metadata for the specified map is returned.
  #
  # @param url The metadata server's base URL.
  # @param mapID The map's identifier number.
  # @return An Array with one or more Hash objects
  def getMapList(baseURL, mapID=nil)
    url = URI(baseURL.to_s+'maps.json')
    response = Net::HTTP.get_response(url)
    data = response.body
    json = JSON.parse(data)
    if (mapID == nil)
      return json
    else
      json.each do |e|
        if (e['id'] == mapID) then return [ e ] end
      end
    end
  end
  
  

  # Retrieve the metadata for a single map. This metadata includes much more
  # information than the "overview" metadata that e.g. the getMapList method
  # provides, including necessary parameters such as height and the actual
  # control points.
  #
  # @param baseURL The server URL from which to retrieve the metadata.
  # @param mapID The map ID.
  # @return A Hash object containing the map metadata
  def getMapMetadata(baseURL, mapID)
    puts 'getMapMetadata'
    puts baseURL.to_s+'maps/'+mapID.to_s+'.json'
    url = URI(baseURL.to_s+'maps/'+mapID.to_s+'.json')
    response = Net::HTTP.get_response(url)
    data = response.body
    JSON.parse(data)
  end
  
  

  # Process the CLI arguments and return a Hash of arguments key-value pairs if
  # the correct arguments exist.
  #
  # @throws Exception If the arguments are invalid
  def getParameters
    params = Hash.new

    # Define the supported options
    opts = GetoptLong.new(
      [ '-?', GetoptLong::NO_ARGUMENT ],
      [ '-d', GetoptLong::REQUIRED_ARGUMENT ],
      [ '-h', GetoptLong::NO_ARGUMENT ],
      [ '-m', GetoptLong::REQUIRED_ARGUMENT ],
      [ '-s', GetoptLong::REQUIRED_ARGUMENT ],
      [ '-w', GetoptLong::REQUIRED_ARGUMENT ],
      [ '-p', GetoptLong::REQUIRED_ARGUMENT ]
    )
    
    opts.each do |opt, arg|
      case opt
        when '-?'
        when '-h'
          raise
        when '-d'
          params['imageDirectory'] = arg
        when '-m'
          params['mapID'] = arg
        when '-s'
          params['metadataServerURL'] = arg
        when '-w'
          params['sleepDelay'] = arg
        when '-p'
          params['publishServerURL'] = arg
      end
    end
    
    params
  end
  
  

  # Make sure the specified parameters are correct.
  #
  # @param params The parameters to check.
  # @return The validate parameters.
  # @throws Exception if a parameter is not correct
  def validateParameters(params)
    if (!params.has_key?('imageDirectory')) then raise 'No image directory parameter found.' else params['imageDirectory'] = params['imageDirectory'].chomp('/') end
    if (!params.has_key?('metadataServerURL')) then raise 'No metadata server parameter found.' end
    if (!params.has_key?('publishServerURL')) then raise 'No publish server parameter found.' end
    if (!File.directory?(params['imageDirectory'])) then raise 'Image directory parameter "'+params['imageDirectory']+'" is not a directory.' end
    if (!File.readable?(params['imageDirectory'])) then raise 'Image directory parameter "'+params['imageDirectory']+'" is not readable.' end
    if (!File.writable?(params['imageDirectory'])) then raise 'Image directory parameter "'+params['imageDirectory']+'" is not writable.' end
    if (params.has_key?('mapID'))
      if (!params['mapID'].is_int?) then raise 'Map ID is not an integer.' else params['mapID'] = params['mapID'].to_i end
    end
    if (params.has_key?('sleepDelay'))
      if (!params['sleepDelay'].is_int?) then raise 'Sleep delay is not an integer.' else params['sleepDelay'] = params['sleepDelay'].to_i end
    end
    params['metadataServerURL'] = URI.parse(params['metadataServerURL'])

    # At this point, everything should be validated and correct
    params
  end



  # Prints usage information to the CLI with an optional error message. If an
  # error message is provided, the returned exit code is changed from zero to
  # one to indicate that there was an error.
  #
  # @param message An optional error message to be printed.
  # @return The exit code that should be used (zero or one).
  def usage(message = nil)
    returnCode = 0
    if (message != nil && message.length > 0)
      puts 'Error: '+message
      puts
      returnCode = 1
    end
    
    puts <<-END
Usage:
#{$0} -d dir -s url [ -w delay ] [ -m id ]

Options:
-?: Display this usage information.
-h: Display this usage information.
-d: A directory containing raw images and tile sets.
-m: An optional map ID to process (instead of all maps).
-s: A server URL from which map metadata can be queried.
-w: An optional delay (in seconds) to wait in between runs.
-p: A server URL where maps are going to be available.
END
    returnCode
  end
end



# If this script is called via CLI, run the converter. Otherwise, assume that
# is it being included in another application, and don't do anything.
#
if (__FILE__ == $0) then TilesetConverter.new().main end

