import std.stdio : writeln;
import std.array : replace;
import std.base64 : Base64URL;
import std.conv : to;
import std.datetime : SysTime, Clock, days;
import std.file : exists, getcwd, readText, tempDir, write;
import std.net.curl : get;
import std.path : buildPath;
import std.string : indexOf;

import helpers : StdoutLogger, parseID, parseQueryString;
import parsers : makeParser, YoutubeVideoURLExtractor;

struct Cache
{
    private StdoutLogger logger;
    private string delegate(string url) downloadAsString;
    string cacheDirectory;

    this(StdoutLogger logger)
    {
        this.logger = logger;
        downloadAsString = (string url) => url.get().idup;
        cacheDirectory = tempDir();
    }

    this(StdoutLogger logger, string delegate(string url) downloadAsString)
    {
        this(logger);
        this.downloadAsString = downloadAsString;
    }

    string getHTML(string url, int itag)
    {
        string cacheKey = url.parseID();
        if(cacheKey == "")
        {
            cacheKey = Base64URL.encode(cast(ubyte[]) url);
        }

        string cachePath = buildPath(cacheDirectory, cacheKey) ~ ".html";
        updateCache(url, cachePath, itag);
        return cachePath.readText();
    }

    private void updateCache(string url, string cachePath, int itag)
    {
        string cachedHTML = cachePath.readText();
        bool shouldRedownload = !cachePath.exists() || isStale(cachedHTML, itag);
        if(shouldRedownload)
        {
            string html = this.downloadAsString(url);
            cachePath.write(html);
        }
    }

    private bool isStale(string html, int itag)
    {
        YoutubeVideoURLExtractor parser = makeParser(html, url => "", logger);
        ulong expire = parser.findExpirationTimestamp(itag);
        return SysTime.fromUnixTime(expire) < Clock.currTime();
    }
}

unittest
{
    writeln("Given AdvancedYoutubeVideoURLExtractor, when cache is stale, should redownload HTML");
    bool downloadAttempted;
    auto downloadAsString = delegate string(string url) {
        downloadAttempted = true;
        return "dQw4w9WgXcQ.html".readText();
    };
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = getcwd();

    string html = cache.getHTML("https://youtu.be/dQw4w9WgXcQ", 18);
    assert(downloadAttempted);
}

unittest
{
    writeln("Given SimpleYoutubeVideoURLExtractor, when cache is stale, should redownload HTML");
    bool downloadAttempted;
    auto downloadAsString = delegate string(string url) {
        downloadAttempted = true;
        return "zoz.html".readText();
    };
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = getcwd();

    string html = cache.getHTML("https://youtu.be/zoz", 18);
    assert(downloadAttempted);
}

unittest
{
    writeln("Given SimpleYoutubeVideoURLExtractor, when cache is fresh, should not download HTML");
    bool downloadAttempted;
    auto downloadAsString = delegate string(string url) {
        downloadAttempted = true;
        return "zoz.html".readText();
    };
    SysTime tomorrow = Clock.currTime() + 1.days;
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = getcwd();
    "zoz-fresh.html".write("zoz.html".readText().dup.replace("expire=1638935038", "expire=" ~ tomorrow.toUnixTime().to!string));

    string html = cache.getHTML("https://youtu.be/zoz-fresh", 18);
    assert(!downloadAttempted);
}

unittest
{
    writeln("Given AdvancedYoutubeVideoURLExtractor, when cache is fresh, should not download HTML");
    bool downloadAttempted;
    auto downloadAsString = delegate string(string url) {
        downloadAttempted = true;
        return "zoz.html".readText();
    };
    SysTime tomorrow = Clock.currTime() + 1.days;
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = getcwd();
    "dQw4w9WgXcQ-fresh.html".write(
            "dQw4w9WgXcQ.html".readText().dup.replace("expire%3D1677997809", "expire%3D" ~ tomorrow.toUnixTime().to!string)
    );

    string html = cache.getHTML("https://youtu.be/dQw4w9WgXcQ-fresh", 18);
    assert(!downloadAttempted);
}
