import std.stdio : writeln;
import std.parallelism : parallel;
import std.algorithm : each, sort;
import std.conv : to;
import std.string : format, split;
import std.file : getcwd, write, append, read, remove;
import std.net.curl : get;
import std.path : buildPath;
import std.range : iota;
import std.getopt;

import helpers;
import parsers;

void main(string[] args)
{
    int itag;
    bool displayFormats;

    auto help = args.getopt(
        std.getopt.config.passThrough,
        std.getopt.config.caseSensitive,
        "f", "Format to download (see -F for available formats)", &itag,
        "F", "List available formats", &displayFormats
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

        ulong length = link.getContentLength();
        writeln("Length = ", length);
        int chunks = 4;
        string[] destinations;
        foreach(i, e; iota(0, chunks).parallel)
        {
            ulong[] offsets = length.calculateOffset(chunks, i);
            string partialLink = format!"%s&range=%d-%d"(link, offsets[0], offsets[1]);
            string partialDestination = format!"%s-%s-%d-%d.mp4.part.%d"(
                parser.getTitle(), parser.getID(), offsets[0], offsets[1], i
            ).sanitizePath();
            destinations ~= partialDestination;
            download(partialDestination, partialLink, url);
        }

        concatenateFiles(destinations, destination);
    }
}

void concatenateFiles(string[] files, string destination)
{
    files.sort!((a, b) => a.split(".")[$ - 1].to!int < b.split(".")[$ -1].to!int);
    foreach(file; files)
    {
        destination.append(file.read());
    }
    files.each!remove;
}

