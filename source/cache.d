import std.stdio : writeln;
import std.array : replace;
import std.base64 : Base64URL;
import std.conv : to;
import std.datetime : SysTime, Clock, days;
import std.file : exists, getcwd, readText, remove, tempDir, write, copy;
import std.net.curl : HTTP;
import std.path : buildPath;
import std.typecons : Flag, Yes, No;
import std.string : indexOf, format, toLower;
import std.regex : ctRegex, matchFirst;
import std.algorithm : canFind, map;
import std.zlib : UnCompress;
import std.json : JSONValue;

import helpers : StdoutLogger, parseID, parseQueryString, parseBaseJSKey, formatTitle, formatSuccess, formatWarning;
import parsers : parseBaseJSURL, YoutubeVideoURLExtractor, SimpleYoutubeVideoURLExtractor, AdvancedYoutubeVideoURLExtractor, EmbeddedSimpleYoutubeVideoURLExtractor, parseYoutubeConfig;

string formatPlayerRequest(string videoId, string poToken, string clientPlayerNonce)
{
    return format!`{
      "cpn": "%s",
      "videoId": "%s",
      "context": {
        "client": {
          "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)",
          "clientName": "WEB_EMBEDDED_PLAYER",
          "clientVersion": "1.20241029.01.00",
          "originalUrl": "https://www.youtube.com/embed/%s",
          "platform": "DESKTOP",
          "clientScreen": "EMBED"
        }
      },
      "serviceIntegrityDimensions": {
        "poToken": "%s"
      }
    }`(clientPlayerNonce, videoId, videoId, poToken);

}

struct Cache
{
    private StdoutLogger logger;
    private string delegate(string url, string[string] additionalHeaders = string[string].init) downloadAsString;
    private Flag!"forceRefresh" forceRefresh;
    string cacheDirectory;
    string poToken;
    string clientPlayerNonce;

    this(StdoutLogger logger, string cookieFile, string poToken, string clientPlayerNonce, Flag!"forceRefresh" forceRefresh = No.forceRefresh)
    {
        this.logger = logger;
        this.forceRefresh = forceRefresh;
        this.poToken = poToken;
        this.clientPlayerNonce = clientPlayerNonce;
        cacheDirectory = tempDir();

        downloadAsString = (string url, string[string] additionalHeaders = string[string].init) {
            string result;
            string responseEncoding;
            auto curl = HTTP(url);
            auto gzip = new UnCompress();
            
            curl.addRequestHeader("Accept-Encoding", "deflate, gzip");
            curl.addRequestHeader("Accept-Language", "en-US,en;q=0.5");
            curl.setUserAgent("com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)");
            curl.verbose(logger.verbose);
            if(cookieFile != "" && cookieFile.readText().canFind("VISITOR_INFO1_LIVE"))
            {
                logger.display("Attaching cookie file " ~ cookieFile);
                curl.setCookieJar(cookieFile);
            }
            if(url.canFind("/v1/player"))
            {
                if(poToken == "")
                {
                    logger.display("No PO token provided, adaptive formats may be broken".formatWarning());
                }
                else
                {
                    logger.display("Attaching proof-of-origin token " ~ poToken);
                }
                string videoId = additionalHeaders["Referer"].parseID();
                curl.setPostData(formatPlayerRequest(videoId, poToken, clientPlayerNonce), "application/json");
                foreach(key, value; additionalHeaders)
                {
                    curl.addRequestHeader(key, value);
                }
            }

            curl.onReceiveHeader = (in char[] key, in char[] value) {
                if(key.idup.toLower() == "content-length")
                {
                    logger.displayVerbose("Length of " ~ url ~ " : " ~ value);
                }
                if(key.idup.toLower() == "content-encoding")
                {
                    responseEncoding = value.idup.toLower();
                }
            };

            curl.onReceive = (ubyte[] chunk) {
                if(responseEncoding == "gzip" || responseEncoding == "deflate")
                {
                    ubyte[] uncompressed = cast(ubyte[]) gzip.uncompress(chunk);
                    result ~= uncompressed.map!(to!(const(char))).to!string;
                }
                else
                {
                    logger.log(formatWarning("Requested gzip content but found unknown encoding in response headers: " ~ responseEncoding));
                    result ~= chunk.map!(to!(const(char))).to!string;
                }
                return chunk.length;
            };
            curl.perform();
            return result;
        };
    }

    version(unittest)
    {
        //to mock curl download calls
        this(StdoutLogger logger, string delegate(string url, string[string] additionalHeaders = string[string].init) downloadAsString, string cookieFile = "", string poToken = "", Flag!"forceRefresh" forceRefresh = No.forceRefresh)
        {
            this(logger, cookieFile, poToken, "MOCK_CPN");
            this.downloadAsString = downloadAsString;
            this.forceRefresh = forceRefresh;
        }
    }

    YoutubeVideoURLExtractor makeParser(string url, int itag)
    {
        string html;
        string player;

        string htmlCachePath = getHTMLCachePath(url) ~ ".html";
        string playerCachePath = getHTMLCachePath(url) ~ ".json";
        if(poToken != "")
        {
            string playerURL = "https://www.youtube.com/youtubei/v1/player?prettyPrint=false";
            updatePlayerCache(url, playerURL, playerCachePath, htmlCachePath, itag);
            html = htmlCachePath.readText();
            player = playerCachePath.readText();
        }
        else
        {
            updateHTMLCache(url, htmlCachePath, itag);
            html = htmlCachePath.readText();
        }

        string baseJSURL = html.parseBaseJSURL();
        string baseJSCachePath = getBaseJSCachePath(baseJSURL) ~ ".js";
        updateBaseJSCache(baseJSURL, baseJSCachePath, itag);
        string baseJS = baseJSCachePath.readText();

        return makeParser(html, baseJS, player, logger);
    }

    private void updateHTMLCache(string url, string htmlCachePath, int itag)
    {
        bool shouldRedownload = forceRefresh || !htmlCachePath.exists() || isStale(htmlCachePath.readText(), "", itag);
        if(shouldRedownload)
        {
            logger.display("Cache miss, downloading HTML...");
            string html = this.downloadAsString(url);
            htmlCachePath.write(html);
        }
        else
        {
            logger.display("Cache hit (" ~ htmlCachePath ~ "), skipping HTML download...");
        }
    }

    private void updatePlayerCache(string url, string playerURL, string playerCachePath, string htmlCachePath, int itag)
    {
        bool shouldRedownload = forceRefresh || !playerCachePath.exists() || isStale("", playerCachePath.readText(), itag);
        if(shouldRedownload)
        {
            logger.display("Cache miss, downloading HTML and player JSON...");
            string html = this.downloadAsString(url);
            htmlCachePath.write(html);

            JSONValue youtubeConfig = html.parseYoutubeConfig();
            string[string] additionalHeaders = [
                "Referer": url,
                "X-Goog-Visitor-Id": youtubeConfig["INNERTUBE_CONTEXT"]["client"]["visitorData"].str,
                "X-Youtube-Bootstrap-Logged-In": "false",
                "X-Youtube-Client-Name:": youtubeConfig["INNERTUBE_CONTEXT"]["client"]["clientName"].str,
                "X-Youtube-Client-Version": youtubeConfig["INNERTUBE_CONTEXT"]["client"]["clientVersion"].str
            ];
            string player = this.downloadAsString(playerURL, additionalHeaders);
            playerCachePath.write(player);
        }
        else
        {
            logger.display("Cache hit (" ~ playerCachePath ~ "), skipping player JSON download...");
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
            logger.display("base.js cache hit (" ~ baseJSCachePath ~ "), skipping download...");
        }
    }

    private bool isStale(string html, string player, int itag)
    {
        YoutubeVideoURLExtractor shallowParser = makeParser(html, "", player, logger);
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

    private YoutubeVideoURLExtractor makeParser(string html, string baseJS, string player, StdoutLogger logger)
    {
        if(player != "")
        {
            return new EmbeddedSimpleYoutubeVideoURLExtractor(html, baseJS, player, poToken, clientPlayerNonce, logger);
        }
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
    writeln("Given SimpleYoutubeVideoURLExtractor, when cache is stale, should redownload HTML".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    bool downloadAttempted;
    auto downloadAsString = delegate string(string url, string[string] additionalHeaders = string[string].init) {
        if(url == "https://youtu.be/zoz")
        {
            downloadAttempted = true;
        }
        return "tests/zoz.html".readText();
    };
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = buildPath(getcwd(), "tests");

    auto parser = cache.makeParser("https://youtu.be/zoz", 18);
    assert(downloadAttempted);
}

unittest
{
    writeln("Given SimpleYoutubeVideoURLExtractor, when cache is fresh, should not download HTML".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    bool downloadAttempted;
    auto downloadAsString = delegate string(string url, string[string] additionalHeaders = string[string].init) {
        if(url == "https://youtu.be/zoz-fresh")
        {
            downloadAttempted = true;
        }
        return "tests/zoz.html".readText();
    };
    SysTime tomorrow = Clock.currTime() + 1.days;
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = buildPath(getcwd(), "tests");

    "tests/zoz-fresh.html".write("tests/zoz.html".readText().dup.replace("expire=1638935038", "expire=" ~ tomorrow.toUnixTime().to!string));

    auto parser = cache.makeParser("https://youtu.be/zoz-fresh", 18);
    assert(!downloadAttempted);
}

unittest
{
    writeln("Given AdvancedYoutubeVideoURLExtractor, when cache is stale, should redownload HTML".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    bool downloadAttempted;
    auto downloadAsString = delegate string(string url, string[string] additionalHeaders = string[string].init) {
        if(url == "https://youtu.be/dQw4w9WgXcQ")
        {
            downloadAttempted = true;
        }
        return "tests/dQw4w9WgXcQ.html".readText();
    };
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = buildPath(getcwd(), "tests");

    auto parser = cache.makeParser("https://youtu.be/dQw4w9WgXcQ", 18);
    assert(downloadAttempted);
}

unittest
{
    writeln("Given AdvancedYoutubeVideoURLExtractor, when cache is fresh, should not download HTML".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    bool downloadAttempted;
    auto downloadAsString = delegate string(string url, string[string] additionalHeaders = string[string].init) {
        if(url == "https://youtu.be/dQw4w9WgXcQ-fresh")
        {
            downloadAttempted = true;
        }
        return "tests/dQw4w9WgXcQ-fresh.html".readText();
    };
    SysTime tomorrow = Clock.currTime() + 1.days;
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = buildPath(getcwd(), "tests");

    //mock previously cached and fresh files
    "tests/dQw4w9WgXcQ-fresh.html".write(
            "tests/dQw4w9WgXcQ.html".readText().dup.replace("expire%3D1677997809", "expire%3D" ~ tomorrow.toUnixTime().to!string)
    );


    auto parser = cache.makeParser("https://youtu.be/dQw4w9WgXcQ-fresh", 18);
    assert(!downloadAttempted);
}

unittest
{
    writeln("When forcing refresh, should download HTML".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    bool downloadAttempted;
    bool baseJSDownloadAttempted;
    auto downloadAsString = delegate string(string url, string[string] additionalHeaders = string[string].init) {
        writeln("downloadAsString : ", url);
        if(url == "https://youtu.be/zoz")
        {
            downloadAttempted = true;
        }
        if(url == "https://www.youtube.com/s/player/0c96dfd3/player_ias.vflset/ar_EG/base.js")
        {
            baseJSDownloadAttempted = true;
        }
        return "tests/zoz.html".readText();
    };
    auto cache = Cache(new StdoutLogger(), downloadAsString, "", "", Yes.forceRefresh);
    cache.cacheDirectory = buildPath(getcwd(), "tests");

    auto parser = cache.makeParser("https://youtu.be/zoz", 18);
    assert(downloadAttempted);
    assert(baseJSDownloadAttempted);
}

unittest
{
    writeln("When base.js is cached, should read from cache".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    "tests/0c96dfd3.js".write("tests/base.min.js".readText());

    bool baseJSDownloadAttempted;
    auto downloadAsString = delegate string(string url, string[string] additionalHeaders = string[string].init) {
        if(url == "https://www.youtube.com/s/player/0c96dfd3/player_ias.vflset/ar_EG/base.js")
        {
            baseJSDownloadAttempted = true;
            return "tests/0c96dfd3.js".readText();
        }
        return "tests/zoz.html".readText();
    };
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = buildPath(getcwd(), "tests");

    auto parser = cache.makeParser("https://youtu.be/zoz", 18);
    assert(!baseJSDownloadAttempted);
}

unittest
{
    writeln("When base.js is not cached, should download it".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    if("tests/0c96dfd3.js".exists())
    {
        "tests/0c96dfd3.js".remove();
    }
    scope(exit)
    {
        "tests/0c96dfd3.js".remove();
    }

    bool baseJSDownloadAttempted;
    auto downloadAsString = delegate string(string url, string[string] additionalHeaders = string[string].init) {
        if(url == "https://www.youtube.com/s/player/0c96dfd3/player_ias.vflset/ar_EG/base.js")
        {
            baseJSDownloadAttempted = true;
            return "tests/base.min.js".readText();
        }
        return "tests/zoz.html".readText();
    };
    auto cache = Cache(new StdoutLogger(), downloadAsString);
    cache.cacheDirectory = buildPath(getcwd(), "tests");

    auto parser = cache.makeParser("https://youtu.be/zoz", 18);
    assert(baseJSDownloadAttempted);
}

unittest
{
    writeln("Given EmbeddedSimpleYoutubeVideoURLExtractor, when cache is fresh, should not download HTML and player".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());

    SysTime tomorrow = Clock.currTime() + 1.days;
    "tests/cvDVjwMXiCs.html".copy("tests/embed-fresh.html");
    "tests/cvDVjwMXiCs.json".copy("tests/embed-fresh.json");
    "tests/embed-fresh.json".write("tests/embed-fresh.json".readText().dup.replace("expire=1730607289", "expire=" ~ tomorrow.toUnixTime().to!string));
    scope(exit)
    {
        remove("tests/embed-fresh.html");
        remove("tests/embed-fresh.json");
    }

    auto downloadAsString = delegate string(string url, string[string] additionalHeaders = string[string].init) {
        assert(false, "downloadAsString should not be called when cache is fresh");
    };
    auto cache = Cache(new StdoutLogger(), downloadAsString, "tests/cookies.txt", "PO_TOKEN_MOCK");
    cache.cacheDirectory = buildPath(getcwd(), "tests");

    auto parser = cache.makeParser("https://youtu.be/embed-fresh", 18);
}

unittest
{
    writeln("Given EmbeddedSimpleYoutubeVideoURLExtractor, when cache is stale, should download HTML and player".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());

    //base.js is already available in tests/ so no need to check it
    bool htmlDownloadAttempted, playerDownloadAttempted;
    auto downloadAsString = delegate string(string url, string[string] additionalHeaders = string[string].init) {
        if(url == "https://youtu.be/cvDVjwMXiCs")
        {
            htmlDownloadAttempted = true;
            return "tests/cvDVjwMXiCs.html".readText();
        }
        if(url == "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")
        {
            playerDownloadAttempted = true;
            return "tests/cvDVjwMXiCs.json".readText();
        }
        assert(false, "downloadAsString called with unknown URL: " ~ url);
    };
    auto cache = Cache(new StdoutLogger(), downloadAsString, "tests/cookies.txt", "PO_TOKEN_MOCK");
    cache.cacheDirectory = buildPath(getcwd(), "tests");

    auto parser = cache.makeParser("https://youtu.be/cvDVjwMXiCs", 18);
    assert(htmlDownloadAttempted && playerDownloadAttempted);
}
