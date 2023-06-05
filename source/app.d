import std.stdio : writef, writeln;
import std.algorithm : each;
import std.conv : to;
import std.string : format;
import std.file : getcwd, write, getSize;
import std.net.curl : get;
import std.path : buildPath;
import std.range : iota;
import std.getopt;

import helpers;
import parsers;
import downloaders;

void main(string[] args)
{
    int itag = 18;
    bool displayFormats;
    bool parallel;
    bool outputURL;

    auto help = args.getopt(
        std.getopt.config.passThrough,
        std.getopt.config.caseSensitive,
        "f", "Format to download (see -F for available formats)", &itag,
        "F", "List available formats", &displayFormats,
        "o|output-url", "Display extracted video URL without downloading it", &outputURL,
        "p|parallel", "Download in 4 parallel connections", &parallel
    );

    if(help.helpWanted || args.length == 1)
    {
        defaultGetoptPrinter("Youtube downloader", help.options);
        return;
    }

    string[] urls = args[1 .. $];

    foreach(url; urls)
    {
        writeln("Handling ", url);
        string html = url.get().idup;
        writeln("Downloaded video HTML");
        write("tmp.html", html);
        YoutubeVideoURLExtractor parser = makeParser(html);
        if(displayFormats)
        {
            writeln("Available formats for ", url);
            parser.getFormats().each!writeln;
            writeln();
            continue;
        }

        parser.getID().writeln();
        parser.getTitle().writeln();
        string filename = format!"%s-%s.mp4"(parser.getTitle(), parser.getID()).sanitizePath();
        filename.writeln();
        string destination = buildPath(getcwd(), filename);
        destination.writeln();
        string link = parser.getURL(itag);

        debug
        {
            write(parser.getID() ~ ".html", html);
            writeln("Found link : ", link);
            writeln();
        }

        if(link == "")
        {
            writeln("Failed to parse video URL");
            continue;
        }
        if(outputURL)
        {
            link.writeln();
            continue;
        }

        writeln("Downloading ", url, " to ", filename);

        Downloader downloader;
        if(parallel)
        {
            logMessage("Using ParallelDownloader");
            downloader = new ParallelDownloader(parser.getID(), parser.getTitle());
        }
        else
        {
            logMessage("Using RegularDownloader");
            downloader = new RegularDownloader((size_t total, size_t current) {
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

