import std.stdio : writef, stdout, writeln;
import std.algorithm : each;
import std.conv : to;
import std.string : format;
import std.file : getcwd, write, getSize;
import std.net.curl : get;
import std.path : buildPath;
import std.range : iota;
import std.logger;
import std.getopt;

import parsers;
import downloaders;
import helpers;

void main(string[] args)
{
    int itag = 18;
    bool displayFormats;
    bool parallel;
    bool outputURL;
    bool verbose;

    auto help = args.getopt(
        std.getopt.config.passThrough,
        std.getopt.config.caseSensitive,
        "f", "Format to download (see -F for available formats)", &itag,
        "F", "List available formats", &displayFormats,
        "o|output-url", "Display extracted video URL without downloading it", &outputURL,
        "p|parallel", "Download in 4 parallel connections", &parallel,
        "v|verbose", "Display debugging messages", &verbose
    );

    if(help.helpWanted || args.length == 1)
    {
        defaultGetoptPrinter("Youtube downloader", help.options);
        return;
    }

    writeln("Verbose mode : ", verbose);

    auto logger = new StdoutLogger(verbose);
    string[] urls = args[1 .. $];

    foreach(url; urls)
    {
        logger.display("Handling ", url);
        string html = url.get().idup;
        logger.displayVerbose("Downloaded video HTML");
        YoutubeVideoURLExtractor parser = makeParser(html, logger);
        if(displayFormats)
        {
            logger.display("Available formats for ", url);
            parser.getFormats().each!(format => logger.display(format));
            logger.display();
            continue;
        }

        logger.display(parser.getID());
        logger.display(parser.getTitle());
        string filename = format!"%s-%s.mp4"(parser.getTitle(), parser.getID()).sanitizePath();
        logger.displayVerbose(filename);
        string destination = buildPath(getcwd(), filename);
        logger.displayVerbose(destination);
        string link = parser.getURL(itag);

        logger.displayVerbose(parser.getID() ~ ".html");
        logger.displayVerbose("Found link : ", link);

        if(link == "")
        {
            logger.error("Failed to parse video URL");
            continue;
        }
        if(outputURL)
        {
            logger.display(link);
            continue;
        }

        logger.display("Downloading ", url, " to ", filename);

        Downloader downloader;
        if(parallel)
        {
            logger.display("Using ParallelDownloader");
            downloader = new ParallelDownloader(logger, parser.getID(), parser.getTitle());
        }
        else
        {
            logger.display("Using RegularDownloader");
            downloader = new RegularDownloader(logger, (size_t total, size_t current) {
                if(current == 0 || total == 0)
                {
                    return 0;
                }
                auto percentage = 100.0 * (cast(float)(current) / total);
                writef!"\r[%.2f %%] %.2f / %.2f MB"(percentage, current / 1024.0 / 1024.0, total / 1024.0 / 1024.0);
                return 0;
            });
        }
        downloader.download(destination, link, url);
    }
}

