import std.logger : info;
import std.regex : ctRegex, matchFirst, escaper, regex, Captures;
import std.algorithm : filter;
import std.conv : to;
import std.file : readText, getcwd, exists, getSize, write;
import std.net.curl : Curl, CurlOption, HTTP, options;
import std.stdio : writef, writeln, File;
import std.string : startsWith, indexOf, format, split;

//video.mp4 20 MB
//video-0-5.mp4.part
//video-5-10.mp4.part
//video-10-15.mp4.part
//video-15-20.mp4.part
//=>concatenate the files
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
                info("Length = ", header["Content-Length:".length + 1 .. $]);
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
    logMessage("cURL result = ", result);
}

ulong getContentLength(string url)
{
    auto http = HTTP(url);
    http.method = HTTP.Method.head;
    http.addRequestHeader("User-Agent", "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:95.0) Gecko/20100101 Firefox/95.0");
    http.perform();
    writeln(http.responseHeaders);
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
    string[string] received = "s=P%3D%3DAi2cZ-qa3KUVLR%3D8ifB5eVi24LUAAtDJdrBXAwub3jYDQICwlGOfArS5Fk6UbM26kHntVmeswXUuJdXq2Rpv0rMIdagIQRw8JQ0qO7&sp=sig&url=https://rr2---sn-f5o5-jhod.googlevideo.com/videoplayback%3Fexpire%3D1677997809%26ei%3DkeIDZIHQKMWC1ga62YWIDQ%26ip%3D105.66.0.249%26id%3Do-ADmt4SY6m6445pG7f4G5f72y1NE48ZiWiqWDA9pi6iQo%26itag%3D396%26aitags%3D133%252C134%252C135%252C136%252C137%252C160%252C242%252C243%252C244%252C247%252C248%252C278%252C394%252C395%252C396%252C397%252C398%252C399%26source%3Dyoutube%26requiressl%3Dyes%26mh%3D7c%26mm%3D31%252C29%26mn%3Dsn-f5o5-jhod%252Csn-h5q7knes%26ms%3Dau%252Crdu%26mv%3Dm%26mvi%3D2%26pl%3D24%26initcwndbps%3D275000%26vprv%3D1%26mime%3Dvideo%252Fmp4%26ns%3DV1YGXTHGUU0a4PsRJqmYKX0L%26gir%3Dyes%26clen%3D5953258%26dur%3D212.040%26lmt%3D1674230525337110%26mt%3D1677975897%26fvip%3D4%26keepalive%3Dyes%26fexp%3D24007246%26c%3DWEB%26txp%3D4537434%26n%3DiRrA3X-4scFA5la%26sparams%3Dexpire%252Cei%252Cip%252Cid%252Caitags%252Csource%252Crequiressl%252Cvprv%252Cmime%252Cns%252Cgir%252Cclen%252Cdur%252Clmt%26lsparams%3Dmh%252Cmm%252Cmn%252Cms%252Cmv%252Cmvi%252Cpl%252Cinitcwndbps%26lsig%3DAG3C_xAwRQIgE-grPIIwKVqUa_siK-FtbLtMME0LPjp9rNlzuvLN7XQCIQCfVt03aw8T9cNgG3u_pFuQafSG4AQeKpgLEHcvodbUjA%253D%253D".parseQueryString();

    string[string] expected = [
        "s": "P%3D%3DAi2cZ-qa3KUVLR%3D8ifB5eVi24LUAAtDJdrBXAwub3jYDQICwlGOfArS5Fk6UbM26kHntVmeswXUuJdXq2Rpv0rMIdagIQRw8JQ0qO7",
        "sp": "sig",
        "url": "https://rr2---sn-f5o5-jhod.googlevideo.com/videoplayback%3Fexpire%3D1677997809%26ei%3DkeIDZIHQKMWC1ga62YWIDQ%26ip%3D105.66.0.249%26id%3Do-ADmt4SY6m6445pG7f4G5f72y1NE48ZiWiqWDA9pi6iQo%26itag%3D396%26aitags%3D133%252C134%252C135%252C136%252C137%252C160%252C242%252C243%252C244%252C247%252C248%252C278%252C394%252C395%252C396%252C397%252C398%252C399%26source%3Dyoutube%26requiressl%3Dyes%26mh%3D7c%26mm%3D31%252C29%26mn%3Dsn-f5o5-jhod%252Csn-h5q7knes%26ms%3Dau%252Crdu%26mv%3Dm%26mvi%3D2%26pl%3D24%26initcwndbps%3D275000%26vprv%3D1%26mime%3Dvideo%252Fmp4%26ns%3DV1YGXTHGUU0a4PsRJqmYKX0L%26gir%3Dyes%26clen%3D5953258%26dur%3D212.040%26lmt%3D1674230525337110%26mt%3D1677975897%26fvip%3D4%26keepalive%3Dyes%26fexp%3D24007246%26c%3DWEB%26txp%3D4537434%26n%3DiRrA3X-4scFA5la%26sparams%3Dexpire%252Cei%252Cip%252Cid%252Caitags%252Csource%252Crequiressl%252Cvprv%252Cmime%252Cns%252Cgir%252Cclen%252Cdur%252Clmt%26lsparams%3Dmh%252Cmm%252Cmn%252Cms%252Cmv%252Cmvi%252Cpl%252Cinitcwndbps%26lsig%3DAG3C_xAwRQIgE-grPIIwKVqUa_siK-FtbLtMME0LPjp9rNlzuvLN7XQCIQCfVt03aw8T9cNgG3u_pFuQafSG4AQeKpgLEHcvodbUjA%253D%253D"
    ];

    assert(received == expected);
}

void logMessage(S...)(S message)
{
    debug
    {
        info(message);
    }
}

string matchOrFail(string pattern, bool escape = false)(string source)
{
    logMessage("Matching ", pattern);
    auto regex = ctRegex!(escape ? pattern.escaper.to!string : pattern);
    return source.matchFirst(regex).matchOrFail();
}

string matchOrFail(string source, string pattern)
{
    logMessage("Matching ", pattern);
    auto regex = regex(pattern);
    return source.matchFirst(regex).matchOrFail();
}

string matchOrFail(Captures!string match)
{
    if(match.empty)
    {
        throw new Exception("Failed to parse encryption steps");
    }
    return match[1];
}

ulong[] calculateOffset(ulong length, int chunks, ulong index)
{
    ulong start = index * (length / chunks);
    ulong end = start + (length / chunks);
    return [start, end];
}

unittest
{
    ulong length = 20 * 1024 * 1024;
    assert([0, 5 * 1024 * 1024] == length.calculateOffset(4, 0));
    assert([5 * 1024 * 1024, 10 * 1024 * 1024] == length.calculateOffset(4, 1));
    assert([10 * 1024 * 1024, 15 * 1024 * 1024] == length.calculateOffset(4, 2));
    assert([15 * 1024 * 1024, 20 * 1024 * 1024] == length.calculateOffset(4, 3));
}
