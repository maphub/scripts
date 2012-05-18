# Maphub scripts

This repository contains a collection of scripts for preparing data and running the maphub portal.

## Seeddata generation

It is assumed that the maphub portal is set up from some seeddata (metadata, maps).

### Download metadata

The script __seeddata/fetch_metadata.rb__ downloads metadata from an OAI-PMH repository and stores them on the file system. Possible execution of the script is as follows:

    ruby imagedownload.rb -s SET(gmd) -u URL -f FORMAT(mods) -o OUTPUT(download) -r TOKEN -v VERB(ListRecords) 

### Download maps

The script __seeddata/imagedownload.rb__ works for the LoC collection only and downloads the actual map images from the LOC gmd set in the form of a directory of map files (*.jp2 format). Possible execution of the script is as follows:

    ruby imagedownload.rb -i FILES(directory of XML files) -o OUTPUT(output directory) -f FORMAT(.gif) -l LOG(log file to be written to OUTPUT) -t TIME(interval) -u URL


### Generating the seed data script

The script __seeddata/generate_loc_seeddata__ generates a YAML file which defines the maphub portal's maps and their metadata. It takes a directory of harvested XML metadata files (option -m) and the directory containing the .jp2 map image files (option -i) as input. The number of maps can *optionally* be restricted to a predefined number (option -n). For example:

    ruby generate-loc-seeddata.rb -i mapdir/ -m metadatadir/ -n 15


## Generating Google Map Overlays

The script __geo/convert.rb__ converts a raw map image into a Google tileset if certain criteria are met. This script currently does not work on Windows, but might work within Cygwin. This script takes input parameters that specify which maps to update and where to get metadata for those maps. The script then attempts to process and create tile sets for those maps. If a tile set is created successfully, the script records the time at which the map was processed (a "checkpoint"). Currently, the checkpoints are stored in a JSON-formatted text file in /tmp. The script can run in a single-use scenario, where the conversion attempts are made and then the script exits, or in a background task scenario, where the script processes the images, waits a specified amount of time, and tries again, ad infinitum.

### Criteria
The script will attempt to convert a raw map image into a tileset if both of the following criteria are satisfied:

1. There exists no previous conversion timestamp or the current timestamp is older than the modification time of the map.
2. There exist more than two control points for the map.

### Usage
Currently, the script can be run in one of two ways: it can be run from the command-line, using typical command-line switches, or it can be run from within another application using a hash of parameters. The current list of possible parameters are as follows:

Run it once:

    ./convert.rb -d ~/data/maps/ -s http://maphubdev.mminf.univie.ac.at:3000/
    
Run it every X seconds

    ./convert.rb -d ~/data/maps/ -s http://maphubdev.mminf.univie.ac.at:3000/ -w 1000

<table>
	<tr>
		<td>CLI</td>
		<td>Hash</td>
		<td>Description</td>
	</tr>
	<tr>
		<td>-?</td>
		<td></td>
		<td>Display CLI usage information.</td>
	</tr>
	<tr>
		<td>-h</td>
		<td></td>
		<td>Display CLI usage information.</td>
	</tr>
	<tr>
		<td>-d</td>
		<td>imageDirectory</td>
		<td>The path to a directory containing a 'raw' subdirectory for raw map images and a 'ts_google' subdirectory for Google tile sets for those map images.</td>
	</tr>
	<tr>
		<td>-m</td>
		<td>mapID</td>
		<td>(Optional) A map ID to process (if possible). If not specified, all maps will be processed (if possible).</td>
	</tr>
	<tr>
		<td>-s</td>
		<td>metadataServerURL</td>
		<td>The root URL for the MapHub server that contains metadata for the maps that are to be processed.</td>
	</tr>
	<tr>
		<td>-w</td>
		<td>sleepDelay</td>
		<td>(Optional) A delay, in seconds, to wait before attempting to re-process the specified maps. If not specified, only one run will be processed and then the script will exit.</td>
	</tr>
</table>