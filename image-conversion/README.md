# Converter script notes
1. Use cases: inputs, outputs?

Current design:
	inputs: metadata server URL and local image directory root
	Scans root/raw for images, compares to root/tilesets. If no google tileset, processes image.
	Checks metadata for updated_at, if newer than tileset image date, re-processes image (into tmpdir then mv).

