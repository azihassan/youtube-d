import std.algorithm : filter;
import std.conv : to;
import std.file : readText, getcwd, exists, getSize, write;
import std.net.curl : Curl, CurlOption;
import std.stdio : writef, writeln, File;
import std.string : startsWith, indexOf, format;

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
