# MapHub Tileset Image Conversion Script
This script converts a raw map image into a Google tileset if certain criteria are met. This script currently does not work on Windows, but might work within Cygwin. This script takes input parameters that specify which maps to update and where to get metadata for those maps. The script then attempts to process and create tile sets for those maps. If a tile set is created successfully, the script records the time at which the map was processed (a "checkpoint"). Currenly, the checkpoints are stored in a JSON-formatted text file in /tmp. The script can run in a single-use scenario, where the conversion attempts are made and then the script exits, or in a background task scenario, where the script processes the images, waits a specified amount of time, and tries again, ad infinitum.

# Criteria
The script will attempt to convert a raw map image into a tileset if both of the following criteria are satisfied:

1. There exists no previous conversion timestamp or the current timestamp is older than the modification time of the map.
2. There exist more than two control points for the map.

# Usage
Currently, the script can be run in one of two ways: it can be run from the command-line, using typical command-line switches, or it can be run from within another application using a hash of parameters. The current list of possible parameters are as follows:

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

