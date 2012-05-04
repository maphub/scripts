#!/usr/bin/env ruby
#
#
#

require 'getoptlong'
require 'uri'

class TilesetConverter
	#
	# Process parameters:
	#   sleepDelay (optional, defaults to one hour)
	#   imageDirectory
	#   metadataServerURL
	@parameters = Hash.new



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
		# Scan through images, compare dates and tileset existence, (re-)process.
		#
		while (true)
			puts "Processing..."
			sleep(@parameters['sleepDelay'])
		end
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
			[ '-s', GetoptLong::REQUIRED_ARGUMENT ]
		)
		
		opts.each do |opt, arg|
			case opt
				when '-?'
				when '-h'
					raise
				when '-d'
					params['imageDirectory'] = arg
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
		if (!params.has_key?('sleepDelay')) then params['sleepDelay'] = 3600; end
		
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
		params['metadataServerURL'] = URI.parse(params['metadataServerURl'])
		
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
			  #{$0} -d dir -s url [ -w delay ]

			Options:
			  -?: Display this usage information.
			  -h: Display this usage information.
			  -d: A directory containing raw images and tile sets.
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
TilesetConverter.new().main if __FILE__==$0

