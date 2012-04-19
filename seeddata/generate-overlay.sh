#!/bin/bash
#
# This script takes the specified image, directory and coordinates and executes
# the appropriate GDAL commands in order to create a transformed set of tiles
# that match the EPSG:4326 projection in the specified directory.
#
#
# It has been tested on Ubuntu Server 11.10 using the following GDAL
# installation instructions:
#
#   sudo apt-get install python-software-properties
#   sudo add-apt-repository ppa:ubuntugis/ubuntugis-unstable
#   sudo apt-get update
#   sudo apt-get install gdal-bin
#   sudo apt-get install python-gdal

#
# This needs to point to the directory that contains gcs.csv.
#
export GDAL_DATA="/usr/share/gdal/1.9"



#
# This is the Google API key used in the resulting Google Maps HTML file.
#
googleAPIKey="ENTER GOOGLE API KEY"



###############################################################################

usage() {
	[ -n "$1" ] && echo $1
	echo "Usage: $0 /path/to/image /path/to/output x,y,lng,lat x,y,lng,lat x,y,lng,lat [ x,y,lng,lat [ ... ] ]"
	exit 1
}

[ $# -lt 5 ] && usage

filePath="$1"
shift
[ -f "${filePath}" ] || usage "Error: \"${filePath}\" is not a file."
[ -r "${filePath}" ] || usage "Error: File \"${filePath}\" is not readable."
fileDirectory=`dirname "${filePath}"`
fileName=`basename "${filePath}"`
fileExtension=${fileName##*.}
filePrefix=${fileName%.*}

outputDirectory="$1"
shift
[ -d "${outputDirectory}" ] || usage "Error: \"${outputDirectory}\" is not a directory."
[ -w "${outputDirectory}" ] || usage "Error: Directory \"${outputDirectory}\" is not writable."
find "${outputDirectory}" -mindepth 1 -delete

translateCommand="gdal_translate -of VRT -a_srs EPSG:4326"
while [ $# -gt 0 ]; do
	coords=`echo $1 | sed 's/,/ /g'`
	shift
	translateCommand="${translateCommand} -gcp ${coords}"
done
translateCommand="${translateCommand} ${filePath} ${outputDirectory}/${filePrefix}-original.vrt"
${translateCommand}

warpCommand="gdalwarp -of VRT -s_srs EPSG:4326 -t_srs EPSG:4326 ${outputDirectory}/${filePrefix}-original.vrt ${outputDirectory}/${filePrefix}-warped.vrt"
${warpCommand}

tileCommand="gdal2tiles.py -k -u /images/tiles/google "
[ -n "${googleAPIKey}" ] && tileCommand="${tileCommand} -g $googleAPIKey"
tileCommand="${tileCommand} ${outputDirectory}/${filePrefix}-warped.vrt ${outputDirectory}"
${tileCommand}
