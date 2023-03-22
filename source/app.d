import std.stdio : writeln;
import std.conv : to;
import std.string : format;
import std.file : getcwd, write;
import std.net.curl : get;
import std.path : buildPath;

import helpers;
import parsers;

void main(string[] args)
{
    if(args.length < 3)
    {
        writeln("Usage : youtube-d -f <itag> <url> [<url> <url>]");
        return;
    }

    int itag = args[2].to!int;
    foreach(url; args[3 .. $])
    {
        string html = url.get().idup;
        YoutubeVideoURLExtractor parser = makeParser(html);
        string filename = format!"%s-%s.mp4"(parser.getTitle(), parser.getID()).sanitizePath();
        string destination = buildPath(getcwd(), filename);
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

        writeln("Downloading ", url, " to ", filename);
        download(destination, link, url);
        writeln();
        writeln();
    }
}
