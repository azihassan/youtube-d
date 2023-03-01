import std.stdio : writef, writeln, File;
import std.string : startsWith;
import std.algorithm : filter;
import std.conv : to;
import std.string : indexOf, format;
import std.array : replace;
import std.file : readText, getcwd, exists, getSize, write;
import std.net.curl : get, Curl, CurlOption;
import std.path : buildPath;
import html;

void main(string[] args)
{
    if(args.length < 2)
    {
        writeln("Usage : youtube-d <url> [<url> <url>]");
        return;
    }
    foreach(url; args[1 .. $])
    {
        auto html = url.get().idup;
        auto parser = YoutubeVideoURLExtractor(html);

        string filename = format!"%s-%s.mp4"(parser.getTitle().replace("|", "-").replace(":", ""), parser.getID()).sanitizePath();
        string destination = buildPath(getcwd(), filename);
        string link = parser.getURL(18);

        debug
        {
            write(parser.getID() ~ ".html", html);
            writeln("Found link : ", link);
            writeln();
        }

        writeln("Downloading ", url, " to ", filename);
        download(destination, link, url);
        writeln();
        writeln();
    }
}

void download(string destination, string url, string referer)
{
    auto http = Curl();
    http.initialize();
    if(destination.exists)
    {
        writeln("Resuming from byte ", destination.getSize());
        http.set(CurlOption.resume_from, destination.getSize());
    }


    auto file = File(destination, "ab");
    http.set(CurlOption.url, url);
    http.set(CurlOption.useragent, "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:95.0) Gecko/20100101 Firefox/95.0");
    http.set(CurlOption.referer, referer);
    http.set(CurlOption.followlocation, true);

    http.onReceive = (ubyte[] data) {
        file.rawWrite(data);
        return data.length;
    };

    debug
    {
        http.onReceiveHeader = (in char[] header) {
            if(header.startsWith("Content-Length"))
            {
                writeln("Length = ", header["Content-Length:".length + 1 .. $]);
            }
        };
    }
    http.onProgress = (size_t total, size_t current, size_t _, size_t __) {
        if(current == 0 || total == 0)
        {
            return 0;
        }
        auto percentage = 100.0 * (cast(float)(current) / total);
        writef!"\r[%.2f %%] %.2f / %.2f MB"(percentage, current / 1024.0 / 1024.0, total / 1024.0 / 1024.0);
        return 0;
    };
    auto result = http.perform();
    debug
    {
        writeln("cURL result = ", result);
    }
}

struct YoutubeVideoURLExtractor
{
    string html;
    private Document parser;

    this(string html)
    {
        this.html = html;
        parser = createDocument(html);
    }

    string getURL(int itag = 18)
    {
        string prefix = format!`itag":%d,"url":`(itag);

        long startIndex = html.indexOf(prefix);
        if(startIndex == -1)
        {
            return "";
        }

        string part = html[startIndex + prefix.length + 1 .. $];
        long endIndex = part.indexOf('"');
        string url = part[0 .. endIndex];
        return url.replace(`\u0026`, "&");
    }

    string getTitle()
    {
        return parser.querySelector("meta[name=title]").attr("content").idup;
    }

    string getID()
    {
        return parser.querySelector("meta[itemprop=videoId]").attr("content").idup;
    }
}

unittest
{
    string html = readText("zoz.html");
    auto extractor = YoutubeVideoURLExtractor(html);

    assert(extractor.getURL(18) == "https://r4---sn-f5o5-jhol.googlevideo.com/videoplayback?expire=1638935038&ei=ntWvYYf_NZiJmLAPtfySkAc&ip=105.66.6.95&id=o-AG7BUTPMmXcFJCtiIUgzrYXlgliHnrjn8IT0b4D_2u8U&itag=18&source=youtube&requiressl=yes&mh=Zy&mm=31%2C29&mn=sn-f5o5-jhol%2Csn-h5qzen7s&ms=au%2Crdu&mv=m&mvi=4&pl=24&initcwndbps=112500&vprv=1&mime=video%2Fmp4&ns=oWqcgbo-7-88Erb0vfdQlB0G&gir=yes&clen=39377316&ratebypass=yes&dur=579.012&lmt=1638885608167129&mt=1638913037&fvip=4&fexp=24001373%2C24007246&c=WEB&txp=3310222&n=RCgHqivzcADgV0inFcU&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Cgir%2Cclen%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRQIhAP5RM2aRT03WZPwBGRWRs25p6T03kecAfGoqqU1tQt0TAiAW-sbLCLqKm9XATrjmhgB5yIlGUeGF1WiWGWvFcVWgkA%3D%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRgIhAJNGheTpD9UVxle1Q9ECIhRMs7Cfl9ZZtqifKo81o-XRAiEAyYKhi3IBXMhIfPyvfpwmj069jMAhaxapC1IhDCl4k90%3D");

    assert(extractor.getURL(22) == "https://r4---sn-f5o5-jhol.googlevideo.com/videoplayback?expire=1638935038&ei=ntWvYYf_NZiJmLAPtfySkAc&ip=105.66.6.95&id=o-AG7BUTPMmXcFJCtiIUgzrYXlgliHnrjn8IT0b4D_2u8U&itag=22&source=youtube&requiressl=yes&mh=Zy&mm=31%2C29&mn=sn-f5o5-jhol%2Csn-h5qzen7s&ms=au%2Crdu&mv=m&mvi=4&pl=24&initcwndbps=112500&vprv=1&mime=video%2Fmp4&ns=oWqcgbo-7-88Erb0vfdQlB0G&cnr=14&ratebypass=yes&dur=579.012&lmt=1638885619798068&mt=1638913037&fvip=4&fexp=24001373%2C24007246&c=WEB&txp=3316222&n=RCgHqivzcADgV0inFcU&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Ccnr%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRQIhAJAAEjw50XBuXW4F5bLVKgzJQ-8HPiVFE9S94uknmEESAiBUZstN7FctoBLg25v5wJeJp5sNqlFziaYNcBdsJn3Feg%3D%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRgIhAJNGheTpD9UVxle1Q9ECIhRMs7Cfl9ZZtqifKo81o-XRAiEAyYKhi3IBXMhIfPyvfpwmj069jMAhaxapC1IhDCl4k90%3D");

    assert(extractor.getTitle() == "اللوبيا المغربية ديال دار سهلة و بنينة سخونة و حنينة");

    assert(extractor.getID() == "sif2JVDhZrQ");
}

string sanitizePath(string path)
{
    bool[dchar] reserved = [
        '<': false,
        '>': false,
        ':': false,
        '"': false,
        '/': false,
        '\\': false,
        '|': false,
        '?': false,
        '*': false,
    ];
    return path.filter!(c => c !in reserved).to!string;
}
