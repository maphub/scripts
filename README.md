# Maphub seedata generation scripts

This repository contains the script for preparing the seed data (maps, metadata) for bootstrapping the Maphub portal.

## Download metadata

This script downloads the metadata required for the LOC gmd set in the form of a directory of XML files. This script is
run first and then the mapdownload.rb script is run. Possible execution of the script is as follows:

    ruby mapdownload.rb -s SET(gmd) -u URL -f FORMAT(mods) -o OUTPUT(download) -r TOKEN -v VERB(ListRecords) 

## Download maps

This script downloads the actual map images from the LOC gmd set in the form of a directory of map files (*.jp2 format)
This script is run after mapdownload.rb. Possible execution of the script is as follows:

    ruby imagedownload.rb -i FILES(directory of XML files) -o OUTPUT(output directory) -f FORMAT(.gif) -l LOG(log file to be written to OUTPUT) -t TIME(interval) -u URL


## Generating the seed data script

This script generates a YAML file which defines the maphub portal's maps and their metadata. It takes a directory of harvested XML metadata files (option -m) and the directory containing the .jp2 map image files (option -i) as input. The number of maps can *optionally* be restricted to a predefined number (option -n). For example:

    ruby generate-loc-seeddata.rb -i mapdir/ -m metadatadir/ -n 15

## Ingesting seed data into the Maphub Portal

tbd.