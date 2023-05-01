import std.stdio : writeln;
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
    int itag;
    bool displayFormats;
    bool parallel;

    auto help = args.getopt(
        std.getopt.config.passThrough,
        std.getopt.config.caseSensitive,
        "f", "Format to download (see -F for available formats)", &itag,
        "F", "List available formats", &displayFormats,
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
        link.writeln();

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
            downloader = new RegularDownloader();
        }
        downloader.download(destination, link, url);
    }
}

