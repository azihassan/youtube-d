import std.stdio : writeln;
import std.array : replace;
import std.base64 : Base64URL;
import std.conv : to;
import std.datetime : SysTime, Clock, days;
import std.file : exists, getcwd, readText, tempDir, write;
import std.net.curl : get;
import std.path : buildPath;
import std.typecons : Flag, Yes, No;
import std.string : indexOf;

import helpers : StdoutLogger, parseID, parseQueryString;
import parsers : parseBaseJSURL, YoutubeVideoURLExtractor, SimpleYoutubeVideoURLExtractor, AdvancedYoutubeVideoURLExtractor;

struct Cache
{
    private StdoutLogger logger;
    private string delegate(string url) downloadAsString;
    private Flag!"forceRefresh" forceRefresh;
    string cacheDirectory;

    this(StdoutLogger logger, Flag!"forceRefresh" forceRefresh = No.forceRefresh)
    {
        this.logger = logger;
        downloadAsString = (string url) => url.get().idup;
        this.forceRefresh = forceRefresh;
        cacheDirectory = tempDir();
    }

    this(StdoutLogger logger, string delegate(string url) downloadAsString, Flag!"forceRefresh" forceRefresh = No.forceRefresh)
    {
        this(logger);
        this.downloadAsString = downloadAsString;
    }

    YoutubeVideoURLExtractor makeParser(string url, int itag)
    {
        string htmlCachePath = getCachePath(url) ~ ".html";
        string baseJSCachePath = getCachePath(url) ~ ".js";
        updateCache(url, htmlCachePath, baseJSCachePath, itag);

        string html = htmlCachePath.readText();
        string baseJS = baseJSCachePath.readText();
        if(html.indexOf("signatureCipher:") == -1)
        {
            return new SimpleYoutubeVideoURLExtractor(html, baseJS, logger);
        }
        return new AdvancedYoutubeVideoURLExtractor(html, baseJS, logger);
    }

    private void updateCache(string url, string htmlCachePath, string baseJSCachePath, int itag)
    {
        bool shouldRedownload = forceRefresh || !htmlCachePath.exists() || isStale(htmlCachePath.readText(), itag);
        if(shouldRedownload)
        {
            logger.display("Cache miss, downloading HTML...");
            string html = this.downloadAsString(url);
            htmlCachePath.write(html);
            string baseJS = this.downloadAsString(html.parseBaseJSURL());
            baseJSCachePath.write(baseJS);
        }
        else
        {
            logger.display("Cache hit, skipping HTML download...");
        }
    }

    private bool isStale(string html, int itag)
    {
        YoutubeVideoURLExtractor shallowParser = html.indexOf("signatureCipher:") == -1
            ? new SimpleYoutubeVideoURLExtractor(html, "", logger)
            : new AdvancedYoutubeVideoURLExtractor(html, "", logger);
        ulong expire = shallowParser.findExpirationTimestamp(itag);
        return SysTime.fromUnixTime(expire) < Clock.currTime();
    }

    private string getCachePath(string url)
    {
        string cacheKey = url.parseID();
        if(cacheKey == "")
        {
            cacheKey = Base64URL.encode(cast(ubyte[]) url);
        }

        return buildPath(cacheDirectory, cacheKey);
    }
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

    auto parser = cache.makeParser("https://youtu.be/zoz", 18);
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
    "zoz-fresh.js".write("base.min.js".readText());

    auto parser = cache.makeParser("https://youtu.be/zoz-fresh", 18);
    assert(!downloadAttempted);
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

    auto parser = cache.makeParser("https://youtu.be/dQw4w9WgXcQ", 18);
    assert(downloadAttempted);
}

unittest
{
    writeln("Given AdvancedYoutubeVideoURLExtractor, when cache is fresh, should not download HTML");
    bool downloadAttempted;
    auto downloadAsString = delegate string(string url) {
        downloadAttempted = true;
        return "dQw4w9WgXcQ-fresh.html".readText();
    };
    SysTime tomorrow = Clock.currTime() + 1.days;
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = getcwd();

    //mock previously cached and fresh files
    "dQw4w9WgXcQ-fresh.js".write("base.min.js".readText());
    "dQw4w9WgXcQ-fresh.html".write(
            "dQw4w9WgXcQ.html".readText().dup.replace("expire%3D1677997809", "expire%3D" ~ tomorrow.toUnixTime().to!string)
    );


    auto parser = cache.makeParser("https://youtu.be/dQw4w9WgXcQ-fresh", 18);
    assert(!downloadAttempted);
}

unittest
{
    writeln("When forcing refresh, should download HTML");
    bool downloadAttempted;
    auto downloadAsString = delegate string(string url) {
        downloadAttempted = true;
        return "zoz.html".readText();
    };
    auto cache = Cache(new StdoutLogger(), downloadAsString, Yes.forceRefresh);
    cache.cacheDirectory = getcwd();

    auto parser = cache.makeParser("https://youtu.be/zoz", 18);
    assert(downloadAttempted);
}
