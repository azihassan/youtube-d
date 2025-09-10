### Youtube-d

![Build status](https://github.com/azihassan/youtube-d/actions/workflows/release.yml/badge.svg "Build status") ![Test status](https://github.com/azihassan/youtube-d/actions/workflows/test.yml/badge.svg "Test status")

A command-line tool to store Youtube videos for offline viewing.

## Usage

Run `youtube-d -h` to display a usage guide.

```bash
$ youtube-d -h
Youtube downloader v0.0.6
-f                 Format to download (see -F for available formats)
-F                 List available formats
-o    --output-url Display extracted video URL without downloading it
-p      --parallel Download in 4 parallel connections
-c       --chunked Download in multiple serial chunks (experimental)
-v       --verbose Display debugging messages
     --no-progress Don't display real-time progress
        --no-cache Skip caching of HTML and base.js
-d    --dethrottle Attempt to dethrottle download speed by solving the N challenge (defaults to true) (deprecated, will be removed soon)
   --no-dethrottle Skip N-challenge dethrottling attempt (deprecated, will be removed soon)
         --version Displays youtube-d version
-h          --help This help information.
```

## Demo on asciinema

[![asciicast](https://asciinema.org/a/omLjWI88J1wsbepeHL4RhGc8u.svg)](https://asciinema.org/a/omLjWI88J1wsbepeHL4RhGc8u)

## Installation

Download the latest release from the [release page](https://github.com/azihassan/youtube-d/releases)

Alternatively, you can build it from source by installing [dub](https://github.com/dlang/dub/releases) and compiling with `dub build -b release`
