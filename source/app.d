import std.stdio : writeln;
import std.string : format;
import std.file : getcwd, write;
import std.net.curl : get;
import std.path : buildPath;

import helpers;
import parsers;

void main(string[] args)
{
    if(args.length < 2)
    {
        writeln("Usage : youtube-d <url> [<url> <url>]");
        return;
    }

    foreach(url; args[1 .. $])
    {
        string html = url.get().idup;
        YoutubeVideoURLExtractor parser = makeParser(html);
        string filename = format!"%s-%s.mp4"(parser.getTitle(), parser.getID()).sanitizePath();
        string destination = buildPath(getcwd(), filename);
        string link = parser.getURL(18);

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
