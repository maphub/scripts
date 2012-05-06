#!/usr/bin/env ruby
#
#
#

require 'date'
require 'fileutils'
require 'getoptlong'
require 'json'
require 'net/http'
require 'tmpdir'
require 'uri'



$GDALRoot = '/usr/share/gdal/1.7'
$tilesetName = 'ts_google'


#
# Create an easy way to test if the specified map ID is an integer.
#
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
# tile set (if any) is removed and the new tile set if moved into its place. If
# a map ID was not specified, the process will sleep and restart the process. If
# a map ID was specified, the process will exit after moving the new tile set to
# the destination.
#
class TilesetConverter
	#
	# Constructor.
	#
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
		
		puts 'Checkpoints: '+@checkpoints.to_s
	end
	
	#
	# Process the images in a loop forever.
	#
	# @throws Exception if the specified parameters are invalid.
	#
	def main(params = nil)
		#
		# Make sure the discovered parameters are valid.
		#
		begin
			#
			# If there are no params passed in, attempt to get them from the CLI.
			#
			if (params == nil) then params = getParameters() end

			#
			# Validate the parameters regardless of whence they came.
			#
			validateParameters(params)
		rescue Exception => e
			if (__FILE__ == $0)
				#
				# We are being used via the CLI, show the error and usage output.
				#
				returnCode = usage(e.message())
				exit returnCode
			else
				#
				# We are being used in another application, throw the current
				# exception up another level.
				#
				raise
			end
		end
		
		#
		# We aren't processing a single map. Scan through all the maps, in
		# each run fetch the map information and attempt to process the map.
		#
		while (true)
			mapID = params.has_key?('mapID') ? params['mapID'] : nil
			
			begin
				#
				# Contact the server and download the metadata for the specified map
				# (or for all maps when mapID is nil--i.e., it was not specified as a
				# parameter.
				#
				metadata = fetchMetadata(params['metadataServerURL'], mapID)
			
				#
				# Process the images.
				#
				processedIDs = []
				metadata.each do |metadatum|
					if (processImage(params, metadatum))
						processedIDs.push(metadatum['id'])
					end
				end
			
				#
				# Update the checkpoints file for the maps we were given.
				#
				updateCheckpoints(processedIDs)
			rescue Exception => e
				#
				# The connection to the server timed out. If we're running the loop
				# we should just keep running and attempt again during the next run.
				# Otherwise the script will just exit.
				#
				puts 'Error: '+e.to_s
			end
			
			#
			# If we were given a map ID, we are only supposed to process once.
			#
			if (params.has_key?('mapID'))
				break
			else
				sleep(params['sleepDelay'])
			end
		end
	end
	
	
	
	#
	# Process the specified image.
	#
	# @return True if the image was processed, false otherwise.
	#
	def processImage(params, metadata)
		url = params['metadataServerURL']
		fileName = metadata['identifier']
		
		#
		# This is used to determine if we should actually process this image or
		# not, based on some criteria (e.g. modification date and whether or not
		# the tile set exists.
		#
		process = false
		
		#
		# See if there is an existing checkpoint and date for this map.
		#
		checkpointDate = nil
		@checkpoints.each do |checkpoint|
			if (checkpoint['id'] == metadata['id'])
				checkpointDate = DateTime.parse(checkpoint['updated_at'])
				break
			end
		end
		
		#
		# If there is no date, then we haven't seen this map before, so we want
		# to process it. Otherwise, we only process the map if the new date is
		# more recent than the old checkpoint date.
		#
		currentDate = DateTime.parse(metadata['updated_at'])
		if (checkpointDate == nil || checkpointDate < currentDate) then process = true end
		
		#
		# We don't want to process an image if there aren't enough control points,
		# regardless of if the times check out...
		#
		controlPoints = fetchControlPoints(url, metadata['id'])
		if (controlPoints.length < 3) then process = false end
		
		if (process)
			puts 'Processing map '+metadata['id']+'...'
			
			#
			# The y values in the database is "wrong": the conversion commands
			# start from the top left corner but MapHub starts from the bottom
			# left. Therefore, we need to "flip" the y values around the median
			# line of the map.
			#
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
					#
					# This point is exactly on the median. Don't anger it.
					#
				end
				cp['y'] = y
				cp
			end
			
			ENV['GDAL_DATA'] = $GDALRoot
			dir = Dir.mktmpdir()
			
			#
			# Translate the image.
			#
			translateCommand = 'gdal_translate -of VRT -a_srs EPSG:4326'
			controlPoints.each do |cp|
				translateCommand = translateCommand+' -gcp '+cp['x'].to_s+' '+cp['y'].to_s+' '+cp['lng']+' '+cp['lat']
			end
			translateCommand = translateCommand+' '+params['imageDirectory']+'/raw/'+fileName+'.jp2 '+dir.to_s+'/'+fileName+'-original.vrt'
			system(translateCommand)

			#
			# Warp the image.
			#			
			warpCommand='gdalwarp -of VRT -s_srs EPSG:4326 -t_srs EPSG:4326 '+dir.to_s+'/'+fileName+'-original.vrt '+dir.to_s+'/'+fileName+'-warped.vrt'
			system(warpCommand)

			#
			# Generate the tile set, placing the generated images in the temporary
			# directory.
			#			
			tileCommand='gdal2tiles.py -n '+dir.to_s+'/'+fileName+'-warped.vrt '+dir.to_s+'/'+$tilesetName
			system(tileCommand)
			
			#
			# Clean up the generated files to leave only the images.
			#
			FileUtils.rm(Dir.glob(dir.to_s+'/'+$tilesetName+'/*.*ml'))
			
			#
			# Remove the current tile set and move the new tile set into its
			# place.
			#
			FileUtils.rm_rf(params['imageDirectory']+'/'+$tilesetName+'/'+fileName)
			FileUtils.mv(dir.to_s+'/'+$tilesetName, params['imageDirectory']+'/'+$tilesetName+'/'+fileName)
			
			return true
		end
		
		return false
	end
	
	
	
	#
	# Retrieve from the server any existing control points for the specified map.
	#
	def fetchControlPoints(url, mapID)
		url = URI(url.to_s+'maps/'+mapID+'/control_points.json')
		response = Net::HTTP.get_response(url)
		data = response.body
		json = JSON.parse(data)
		return json
	end
	
	
	
	#
	# This could probably be improved...
	#
	def updateCheckpoints(mapIDs)
		now = DateTime.now.to_s

		#
		# Go through the processed IDs and update them in-place within the
		# checkpoints Array. If the processed ID doesn't exist in the checkpoints
		# Array, append it.
		#		
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
		puts 'Checkpoints: '+@checkpoints.to_s

		#
		# Save the new checkpoints to the file.
		#		
		json = JSON.generate(@checkpoints)
		file = File.new(@checkpointsFile, 'w')
		file.write(json)
		file.close
	end
	
	
	
	#
	# Retrieve metadata from the server. If a map ID is specified, metadata for
	# only that map will be retrieved and an Array with a single Hash element
	# containing the JSON data is returned. If no map ID is specified, all maps
	# will be retrieved and an Array of Hash objects (each of which represents a
	# map) will be returned.
	#
	# @param url The metadata server's base URL.
	# @param mapID The map's identifier number.
	# @return An Array with one or more Hash objects.
	#
	def fetchMetadata(baseURL, mapID=nil)
		if (mapID != nil)
			url = URI(baseURL.to_s+'maps/'+mapID.to_s+'.json')
		else
			url = URI(baseURL.to_s+'maps.json')
		end
		
		response = Net::HTTP.get_response(url)
		data = response.body
		json = JSON.parse(data)
		return (mapID == nil) ? json : [ json ]
	end
	
	
	
	#
	# Process the CLI arguments and return a Hash of arguments key-value pairs if
	# the correct arguments exist.
	#
	# @throws Exception If the arguments are invalid.
	#
	def getParameters
		params = Hash.new

		#
		# Define the supported options.
		#
		opts = GetoptLong.new(
			[ '-?', GetoptLong::NO_ARGUMENT ],
			[ '-d', GetoptLong::REQUIRED_ARGUMENT ],
			[ '-h', GetoptLong::NO_ARGUMENT ],
			[ '-m', GetoptLong::REQUIRED_ARGUMENT ],
			[ '-s', GetoptLong::REQUIRED_ARGUMENT ]
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
			end
		end
		
		return params
	end
	
	
	
	#
	# Make sure the provided arguments are correct.
	#
	def validateParameters(params)
		#
		# Set the defaults.
		#
		if (!params.has_key?('sleepDelay')) then params['sleepDelay'] = 10; end
		
		#
		# Some initial error checking.
		#
		if (!params.has_key?('imageDirectory')) then raise 'No image directory parameter found.' end
		if (!params.has_key?('metadataServerURL')) then raise 'No metadata server parameter found.' end
		
		#
		# Parameter type/existence checking.
		#
		if (!File.directory?(params['imageDirectory'])) then raise 'Image directory parameter "'+params['imageDirectory']+'" is not a directory.' end
		if (!File.readable?(params['imageDirectory'])) then raise 'Image directory parameter "'+params['imageDirectory']+'" is not readable.' end
		if (!File.writable?(params['imageDirectory'])) then raise 'Image directory parameter "'+params['imageDirectory']+'" is not writable.' end
		if (params.has_key?('mapID'))
			if (!params['mapID'].is_int?) then raise 'Map ID is not an integer.' else params['mapID'] = params['mapID'].to_i end
		end
		params['metadataServerURL'] = URI.parse(params['metadataServerURL'])
		
		#
		# At this point, everything should be validated and correct.
		#
		return params
	end



	def usage(message = nil)
		returnCode = 1
		if (message != nil && message.length > 0)
			puts 'Error: '+message
			puts
			returnCode = 0
		end
		
		#
		# Excellent heredoc gsub tip found at:
		# http://rubyquicktips.com/post/4438542511/heredoc-and-indent
		#
		puts <<-END.gsub(/\t{3}/, '')
			Usage:
			  #{$0} -d dir -s url [ -w delay ] [ -m id ]

			Options:
			  -?: Display this usage information.
			  -h: Display this usage information.
			  -d: A directory containing raw images and tile sets.
			  -m: An optional map ID to process (instead of all maps).
			  -s: A server URL from which map metadata can be queried.
			  -w: An optional delay (in seconds) to wait in between runs.
		END
		
		return returnCode
	end
end



#
# If this script is called via CLI, run the converter. Otherwise, assume that
# is it being included in another application, and don't do anything.
#
if (__FILE__ == $0) then TilesetConverter.new().main end

