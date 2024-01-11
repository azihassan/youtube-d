import std.stdio : writeln;
import std.array : replace;
import std.base64 : Base64URL;
import std.conv : to;
import std.datetime : SysTime, Clock, days;
import std.file : exists, getcwd, readText, remove, tempDir, write;
import std.net.curl : get;
import std.path : buildPath;
import std.typecons : Flag, Yes, No;
import std.string : indexOf;
import std.regex : ctRegex, matchFirst;

import helpers : StdoutLogger, parseID, parseQueryString, parseBaseJSKey;
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
        this.forceRefresh = forceRefresh;
    }

    YoutubeVideoURLExtractor makeParser(string url, int itag)
    {
        string htmlCachePath = getHTMLCachePath(url) ~ ".html";
        updateHTMLCache(url, htmlCachePath, itag);
        string html = htmlCachePath.readText();

        string baseJSURL = html.parseBaseJSURL();
        string baseJSCachePath = getBaseJSCachePath(baseJSURL) ~ ".js";
        updateBaseJSCache(baseJSURL, baseJSCachePath, itag);
        string baseJS = baseJSCachePath.readText();

        return makeParser(html, baseJS, logger);
    }

    private void updateHTMLCache(string url, string htmlCachePath, int itag)
    {
        bool shouldRedownload = forceRefresh || !htmlCachePath.exists() || isStale(htmlCachePath.readText(), itag);
        if(shouldRedownload)
        {
            logger.display("Cache miss, downloading HTML...");
            string html = this.downloadAsString(url);
            htmlCachePath.write(html);
        }
        else
        {
            logger.display("Cache hit, skipping HTML download...");
        }
    }

    private void updateBaseJSCache(string url, string baseJSCachePath, int itag)
    {
        bool shouldRedownload = forceRefresh || !baseJSCachePath.exists();
        if(shouldRedownload)
        {
            logger.display("base.js cache miss, downloading from " ~ url);
            string baseJS = this.downloadAsString(url);
            baseJSCachePath.write(baseJS);
        }
        else
        {
            logger.display("base.js cache hit, skipping download...");
        }
    }

    private bool isStale(string html, int itag)
    {
        YoutubeVideoURLExtractor shallowParser = makeParser(html, "", logger);
        ulong expire = shallowParser.findExpirationTimestamp(itag);
        return SysTime.fromUnixTime(expire) < Clock.currTime();
    }

    private string getHTMLCachePath(string url)
    {
        string cacheKey = url.parseID();
        if(cacheKey == "")
        {
            cacheKey = Base64URL.encode(cast(ubyte[]) url);
        }

        return buildPath(cacheDirectory, cacheKey);
    }

    private string getBaseJSCachePath(string url)
    {
        string cacheKey = url.parseBaseJSKey();
        if(cacheKey == "")
        {
            cacheKey = Base64URL.encode(cast(ubyte[]) url);
        }

        return buildPath(cacheDirectory, cacheKey);
    }

    private YoutubeVideoURLExtractor makeParser(string html, string baseJS, StdoutLogger logger)
    {
        immutable urlRegex = ctRegex!`"itag":\d+,"url":"(.*?)"`;
        if(!html.matchFirst(urlRegex).empty)
        {
            return new SimpleYoutubeVideoURLExtractor(html, baseJS, logger);
        }
        return new AdvancedYoutubeVideoURLExtractor(html, baseJS, logger);
    }
}

unittest
{
    writeln("Given SimpleYoutubeVideoURLExtractor, when cache is stale, should redownload HTML");
    bool downloadAttempted;
    auto downloadAsString = delegate string(string url) {
        if(url == "https://youtu.be/zoz")
        {
            downloadAttempted = true;
        }
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
        if(url == "https://youtu.be/zoz-fresh")
        {
            downloadAttempted = true;
        }
        return "zoz.html".readText();
    };
    SysTime tomorrow = Clock.currTime() + 1.days;
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = getcwd();

    "zoz-fresh.html".write("zoz.html".readText().dup.replace("expire=1638935038", "expire=" ~ tomorrow.toUnixTime().to!string));

    auto parser = cache.makeParser("https://youtu.be/zoz-fresh", 18);
    assert(!downloadAttempted);
}

unittest
{
    writeln("Given AdvancedYoutubeVideoURLExtractor, when cache is stale, should redownload HTML");
    bool downloadAttempted;
    auto downloadAsString = delegate string(string url) {
        if(url == "https://youtu.be/dQw4w9WgXcQ")
        {
            downloadAttempted = true;
        }
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
        if(url == "https://youtu.be/dQw4w9WgXcQ-fresh")
        {
            downloadAttempted = true;
        }
        return "dQw4w9WgXcQ-fresh.html".readText();
    };
    SysTime tomorrow = Clock.currTime() + 1.days;
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = getcwd();

    //mock previously cached and fresh files
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
    bool baseJSDownloadAttempted;
    auto downloadAsString = delegate string(string url) {
        writeln("downloadAsString : ", url);
        if(url == "https://youtu.be/zoz")
        {
            downloadAttempted = true;
        }
        if(url == "https://www.youtube.com/s/player/0c96dfd3/player_ias.vflset/ar_EG/base.js")
        {
            baseJSDownloadAttempted = true;
        }
        return "zoz.html".readText();
    };
    auto cache = Cache(new StdoutLogger(), downloadAsString, Yes.forceRefresh);
    cache.cacheDirectory = getcwd();

    auto parser = cache.makeParser("https://youtu.be/zoz", 18);
    assert(downloadAttempted);
    assert(baseJSDownloadAttempted);
}

unittest
{
    writeln("When base.js is cached, should read from cache");
    "0c96dfd3.js".write("base.min.js".readText());

    bool baseJSDownloadAttempted;
    auto downloadAsString = delegate string(string url) {
        if(url == "https://www.youtube.com/s/player/0c96dfd3/player_ias.vflset/ar_EG/base.js")
        {
            baseJSDownloadAttempted = true;
            return "0c96dfd3.js".readText();
        }
        return "zoz.html".readText();
    };
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = getcwd();

    auto parser = cache.makeParser("https://youtu.be/zoz", 18);
    assert(!baseJSDownloadAttempted);
}

unittest
{
    writeln("When base.js is not cached, should download it");
    if("0c96dfd3.js".exists())
    {
        "0c96dfd3.js".remove();
    }
    scope(exit)
    {
        "0c96dfd3.js".remove();
    }

    bool baseJSDownloadAttempted;
    auto downloadAsString = delegate string(string url) {
        if(url == "https://www.youtube.com/s/player/0c96dfd3/player_ias.vflset/ar_EG/base.js")
        {
            baseJSDownloadAttempted = true;
            return "base.min.js".readText();
        }
        return "zoz.html".readText();
    };
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = getcwd();

    auto parser = cache.makeParser("https://youtu.be/zoz", 18);
    assert(baseJSDownloadAttempted);
}
