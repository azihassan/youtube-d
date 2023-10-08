### Youtube-d

A command-line tool to store Youtube videos for offline viewing.

## Usage

Run `youtube-d -h` to display a usage guide.

```bash
$ youtube-d -h
Youtube downloader
-f               Format to download (see -F for available formats)
-F               List available formats
-o  --output-url Display extracted video URL without downloading it
-p    --parallel Download in 4 parallel connections
-v     --verbose Display debugging messages
   --no-progress Don't display real-time progress
-h        --help This help information.

```

## Demo on asciinema

[![asciicast](https://asciinema.org/a/DufBt4G5ArFvfPVLzVzfbfwnD.svg)](https://asciinema.org/a/DufBt4G5ArFvfPVLzVzfbfwnD)

## Installation

Download the latest release from the [release page](https://github.com/azihassan/youtube-d/releases)

Alternatively, you can build it from source by installing [dub](https://github.com/dlang/dub/releases) and compiling with `dub build -b release`
