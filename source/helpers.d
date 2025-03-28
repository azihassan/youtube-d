import std.logger;
import std.stdio : writeln, writefln, File, stdout;
import std.regex : ctRegex, matchFirst, escaper, regex, Captures;
import std.algorithm : filter;
import std.conv : to;
import std.net.curl : HTTP;
import std.string : split, indexOf, startsWith;
import std.format : formattedRead;

ulong getContentLength(string url)
{
    auto http = HTTP(url);
    http.method = HTTP.Method.head;
    http.addRequestHeader("User-Agent", "com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)");
    http.perform();
    if(http.statusLine.code >= 400)
    {
        throw new Exception("Failed with status " ~ http.statusLine.code.to!string);
    }
    return http.responseHeaders["content-length"].to!ulong;
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

string[string] parseQueryString(string input)
{
    auto questionMarkIndex = input.indexOf("?");
    if(questionMarkIndex != -1)
    {
        input = input[questionMarkIndex + 1 .. $];
    }
    string[string] result;
    foreach(params; input.split("&"))
    {
        string[] parts = params.split("=");
        result[parts[0]] = parts[1];
    }
    return result;
}

unittest
{
    writeln("Should parse query string into associative array".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    string[string] received = "s=P%3D%3DAi2cZ-qa3KUVLR%3D8ifB5eVi24LUAAtDJdrBXAwub3jYDQICwlGOfArS5Fk6UbM26kHntVmeswXUuJdXq2Rpv0rMIdagIQRw8JQ0qO7&sp=sig&url=https://rr2---sn-f5o5-jhod.googlevideo.com/videoplayback%3Fexpire%3D1677997809%26ei%3DkeIDZIHQKMWC1ga62YWIDQ%26ip%3D105.66.0.249%26id%3Do-ADmt4SY6m6445pG7f4G5f72y1NE48ZiWiqWDA9pi6iQo%26itag%3D396%26aitags%3D133%252C134%252C135%252C136%252C137%252C160%252C242%252C243%252C244%252C247%252C248%252C278%252C394%252C395%252C396%252C397%252C398%252C399%26source%3Dyoutube%26requiressl%3Dyes%26mh%3D7c%26mm%3D31%252C29%26mn%3Dsn-f5o5-jhod%252Csn-h5q7knes%26ms%3Dau%252Crdu%26mv%3Dm%26mvi%3D2%26pl%3D24%26initcwndbps%3D275000%26vprv%3D1%26mime%3Dvideo%252Fmp4%26ns%3DV1YGXTHGUU0a4PsRJqmYKX0L%26gir%3Dyes%26clen%3D5953258%26dur%3D212.040%26lmt%3D1674230525337110%26mt%3D1677975897%26fvip%3D4%26keepalive%3Dyes%26fexp%3D24007246%26c%3DWEB%26txp%3D4537434%26n%3DiRrA3X-4scFA5la%26sparams%3Dexpire%252Cei%252Cip%252Cid%252Caitags%252Csource%252Crequiressl%252Cvprv%252Cmime%252Cns%252Cgir%252Cclen%252Cdur%252Clmt%26lsparams%3Dmh%252Cmm%252Cmn%252Cms%252Cmv%252Cmvi%252Cpl%252Cinitcwndbps%26lsig%3DAG3C_xAwRQIgE-grPIIwKVqUa_siK-FtbLtMME0LPjp9rNlzuvLN7XQCIQCfVt03aw8T9cNgG3u_pFuQafSG4AQeKpgLEHcvodbUjA%253D%253D".parseQueryString();

    string[string] expected = [
        "s": "P%3D%3DAi2cZ-qa3KUVLR%3D8ifB5eVi24LUAAtDJdrBXAwub3jYDQICwlGOfArS5Fk6UbM26kHntVmeswXUuJdXq2Rpv0rMIdagIQRw8JQ0qO7",
        "sp": "sig",
        "url": "https://rr2---sn-f5o5-jhod.googlevideo.com/videoplayback%3Fexpire%3D1677997809%26ei%3DkeIDZIHQKMWC1ga62YWIDQ%26ip%3D105.66.0.249%26id%3Do-ADmt4SY6m6445pG7f4G5f72y1NE48ZiWiqWDA9pi6iQo%26itag%3D396%26aitags%3D133%252C134%252C135%252C136%252C137%252C160%252C242%252C243%252C244%252C247%252C248%252C278%252C394%252C395%252C396%252C397%252C398%252C399%26source%3Dyoutube%26requiressl%3Dyes%26mh%3D7c%26mm%3D31%252C29%26mn%3Dsn-f5o5-jhod%252Csn-h5q7knes%26ms%3Dau%252Crdu%26mv%3Dm%26mvi%3D2%26pl%3D24%26initcwndbps%3D275000%26vprv%3D1%26mime%3Dvideo%252Fmp4%26ns%3DV1YGXTHGUU0a4PsRJqmYKX0L%26gir%3Dyes%26clen%3D5953258%26dur%3D212.040%26lmt%3D1674230525337110%26mt%3D1677975897%26fvip%3D4%26keepalive%3Dyes%26fexp%3D24007246%26c%3DWEB%26txp%3D4537434%26n%3DiRrA3X-4scFA5la%26sparams%3Dexpire%252Cei%252Cip%252Cid%252Caitags%252Csource%252Crequiressl%252Cvprv%252Cmime%252Cns%252Cgir%252Cclen%252Cdur%252Clmt%26lsparams%3Dmh%252Cmm%252Cmn%252Cms%252Cmv%252Cmvi%252Cpl%252Cinitcwndbps%26lsig%3DAG3C_xAwRQIgE-grPIIwKVqUa_siK-FtbLtMME0LPjp9rNlzuvLN7XQCIQCfVt03aw8T9cNgG3u_pFuQafSG4AQeKpgLEHcvodbUjA%253D%253D"
    ];

    assert(received == expected);
}

string matchOrFail(string pattern, bool escape = false)(string source)
{
    trace("Matching ", pattern);
    auto regex = ctRegex!(escape ? pattern.escaper.to!string : pattern);
    return source.matchFirst(regex).matchOrFail(pattern);
}

string matchOrFail(string source, string pattern)
{
    trace("Matching ", pattern);
    auto regex = regex(pattern);
    return source.matchFirst(regex).matchOrFail(pattern);
}

string matchOrFail(Captures!string match, string pattern = "")
{
    if(match.empty)
    {
        throw new Exception("Failed to match regular expression " ~ pattern);
    }
    return match[1];
}

class StdoutLogger : Logger
{
    bool verbose;
    private File stream;

    this(bool verbose = false, File stream = stdout) @safe
    {
        super(LogLevel.info);
        this.verbose = verbose;
        this.stream = stream;
    }

    void displayVerbose(S...)(S message)
    {
        if(this.verbose)
        {
            log(message);
        }
    }

    void display(S...)(S message)
    {
        log(message);
    }

    override void writeLogMsg(ref LogEntry payload)
    {
        stream.writeln(payload.msg);
    }
}

version(unittest)
{
    import std.file : readText;
    import std.string : splitLines, strip;
}

unittest
{
    writeln("Should log verbose output in verbose mode".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto logs = File("tests/logs.txt", "w");
    auto logger = new StdoutLogger(true, logs);
    logger.displayVerbose("should log this verbose message");
    logger.display("should log this message");
    logs.flush();

    assert("tests/logs.txt".readText().strip().splitLines() == [
            "should log this verbose message",
            "should log this message"
    ]);
    writeln("Finished");
}

unittest
{
    writeln("Should skip verbose output in non verbose mode".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto logs = File("tests/logs.txt", "w");
    auto logger = new StdoutLogger(false, logs);
    logger.displayVerbose("should skip this verbose message");
    logger.display("should log this message");
    logs.flush();

    assert("tests/logs.txt".readText().splitLines() == [
            "should log this message"
    ]);
}

string formatSuccess(string input)
{
    version(Windows)
    {
        return input;
    }
    else
    {
        return "\033[0;32m" ~ input ~ "\033[0m";
    }
}

string formatWarning(string input)
{
    version(Windows)
    {
        return input;
    }
    else
    {
        return "\033[0;33m" ~ input ~ "\033[0m";
    }
}

string formatError(string input)
{
    version(Windows)
    {
        return input;
    }
    else
    {
        return "\033[1;31m" ~ input ~ "\033[0m";
    }
}

string formatTitle(string input)
{
    version(Windows)
    {
        return input;
    }
    else
    {
        return "\033[1m" ~ input ~ "\033[0m";
    }
}

string parseID(string url)
{
    string id;
    if(!url.startsWith("https://"))
    {
        url = "https://" ~ url;
    }

    if(url.indexOf("?v=") != -1)
    {
        return url[url.indexOf("?") + 1 .. $].parseQueryString()["v"];
    }
    if(url.indexOf("youtu.be") != -1)
    {
        url.formattedRead!"https://youtu.be/%s"(id);
    }
    if(url.indexOf("shorts") != -1)
    {
        if(url.startsWith("https://www"))
        {
            url.formattedRead!"https://www.youtube.com/shorts/%s"(id);
        }
        else
        {
            url.formattedRead!"https://youtube.com/shorts/%s"(id);
        }
    }
    return id;
}

unittest
{
    writeln("Should parse video ID".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    assert("https://www.youtube.com/watch?v=-H-Fno9xbE4".parseID() == "-H-Fno9xbE4");
    assert("https://youtu.be/-H-Fno9xbE4".parseID() == "-H-Fno9xbE4");
    assert("https://www.youtube.com/shorts/_tT2ldpZHek".parseID() == "_tT2ldpZHek");
    assert("https://youtube.com/shorts/_tT2ldpZHek".parseID() == "_tT2ldpZHek");
    assert("qlsdkqsldkj".parseID() == "");
}

string parseBaseJSKey(string url)
{
    string id;
    if(url.startsWith("https://"))
    {
        url = url["https://".length .. $];
    }
    if(url.startsWith("www.youtube.com"))
    {
        url = url["www.youtube.com".length .. $];
    }
    return url.split("/")[3];
}

unittest
{
    writeln("Should parse player name".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    assert("/s/player/0c96dfd3/player_ias.vflset/ar_EG/base.js".parseBaseJSKey() == "0c96dfd3");
    assert("https://www.youtube.com/s/player/0c96dfd3/player_ias.vflset/ar_EG/base.js".parseBaseJSKey() == "0c96dfd3");
    assert("www.youtube.com/s/player/0c96dfd3/player_ias.vflset/ar_EG/base.js".parseBaseJSKey() == "0c96dfd3");
}
