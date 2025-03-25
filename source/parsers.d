import std.json;
import std.net.curl : get;
import std.uri : decodeComponent, encodeComponent;
import std.stdio;
import std.typecons : tuple, Tuple;
import std.conv : to;
import std.array : replace;
import std.file : readText;
import std.string : indexOf, format, lastIndexOf, split, strip, toStringz, startsWith;
import std.regex : ctRegex, matchFirst, escaper;
import std.algorithm : canFind, filter, reverse, map;
import std.format : formattedRead;

import helpers : parseQueryString, matchOrFail, StdoutLogger, formatTitle, formatSuccess, formatError, formatWarning;

import html;
import duktape;

abstract class YoutubeVideoURLExtractor
{
    protected string html;
    protected Document parser;
    protected StdoutLogger logger;

    abstract public string getURL(int itag, bool attemptDethrottle = false);
    abstract public ulong findExpirationTimestamp(int itag);

    public void failIfUnplayable()
    {
        auto playabilityStatus = html.matchFirst(ctRegex!`"playabilityStatus":\{"status":"(.*?)",`);
        if(playabilityStatus.empty)
        {
            logger.display("Warning: playability status could not be parsed".formatWarning);
            return;
        }
        if(playabilityStatus[1] != "OK")
        {
            throw new Exception("Video is unplayable because of status " ~ playabilityStatus[1]);
        }
    }

    public string getTitle()
    {
        try
        {
            JSONValue playerResponse = findInitialPlayerResponse();
            return playerResponse["videoDetails"]["title"].str;
        }
        catch(Exception e)
        {
            return "Unknown title";
        }

    }

    public string getID()
    {
        JSONValue playerResponse = findInitialPlayerResponse();
        return playerResponse["videoDetails"]["videoId"].str;
    }

    public YoutubeFormat getFormat(int itag)
    {
        YoutubeFormat[] formats = getFormats("formats") ~ getFormats("adaptiveFormats");
        auto match = formats.filter!(format => format.itag == itag);
        if(match.empty)
        {
            throw new Exception("Unknown itag : " ~ itag.to!string);
        }
        return match.front();
    }

    public YoutubeFormat[] getFormats()
    {
        return getFormats("formats") ~ getFormats("adaptiveFormats");
    }

    private YoutubeFormat[] getFormats(string formatKey)
    {
        string streamingData = html.matchOrFail!`"streamingData":(.*?),"player`;
        auto json = streamingData.parseJSON();
        if(formatKey !in json)
        {
            return [];
        }
        YoutubeFormat[] formats;
        foreach(format; json[formatKey].array)
        {
            ulong contentLength = "contentLength" in format ? format["contentLength"].str.to!ulong : 0UL;
            string quality = "qualityLabel" in format ? format["qualityLabel"].str : format["quality"].str;
            AudioVisual[] audioVisual;
            string mimeType;
            string codecs;
            format["mimeType"].str.formattedRead!"%s; codecs=\"%s\""(mimeType, codecs);
            if(codecs.canFind(","))
            {
                audioVisual = [AudioVisual.AUDIO, AudioVisual.VIDEO];
            }
            else if(mimeType.startsWith("video"))
            {
                audioVisual = [AudioVisual.VIDEO];
            }
            else if(mimeType.startsWith("audio"))
            {
                audioVisual = [AudioVisual.AUDIO];
            }
            formats ~= YoutubeFormat(
                cast(int) format["itag"].integer,
                contentLength,
                quality,
                format["mimeType"].str,
                audioVisual
            );
        }
        return formats;
    }

    protected JSONValue findInitialPlayerResponse()
    {
        foreach(script; parser.querySelectorAll("body > script"))
        {
            if(script.text.canFind("var ytInitialPlayerResponse = {"))
            {
                return script.text.replace("var ytInitialPlayerResponse = ", "").parseJSON();
            }
        }
        throw new Exception("ytInitialPlayerResponse couldn't be parsed, video metadata not found");
    }
}

class SimpleYoutubeVideoURLExtractor : YoutubeVideoURLExtractor
{
    private string baseJS;
    this(string html, StdoutLogger logger)
    {
        this.html = html;
        this.logger = logger;
        parser = createDocument(html);
        failIfUnplayable();
    }

    this(string html, string baseJS, StdoutLogger logger)
    {
        this(html, logger);
        this.baseJS = baseJS;
    }

    override string getURL(int itag, bool attemptDethrottle = false)
    {
        string url = html
            .matchOrFail(`"itag":` ~ itag.to!string ~ `,"url":"(.*?)"`)
            .replace(`\u0026`, "&");

        string[string] queryString = url.parseQueryString();
        if(baseJS == "" || !attemptDethrottle || "n" !in queryString)
        {
            return url;
        }

        string n = queryString["n"];
        logger.displayVerbose("Found n : ", n);
        auto solver = ThrottlingAlgorithm(baseJS, logger);
        string solvedN = solver.solve(n);
        logger.displayVerbose("Solved n : ", solvedN);
        return url.replace("&n=" ~ n, "&n=" ~ solvedN);
    }

    override ulong findExpirationTimestamp(int itag)
    {
        string videoURL = getURL(itag);
        string[string] params = videoURL.parseQueryString();
        return params["expire"].to!ulong;
    }
}

unittest
{
    writeln("Should parse video URL and metadata from regular videos".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    string html = readText("tests/zoz.html");
    auto extractor = new SimpleYoutubeVideoURLExtractor(html, new StdoutLogger());

    assert(extractor.getURL(18) == "https://r4---sn-f5o5-jhol.googlevideo.com/videoplayback?expire=1638935038&ei=ntWvYYf_NZiJmLAPtfySkAc&ip=105.66.6.95&id=o-AG7BUTPMmXcFJCtiIUgzrYXlgliHnrjn8IT0b4D_2u8U&itag=18&source=youtube&requiressl=yes&mh=Zy&mm=31%2C29&mn=sn-f5o5-jhol%2Csn-h5qzen7s&ms=au%2Crdu&mv=m&mvi=4&pl=24&initcwndbps=112500&vprv=1&mime=video%2Fmp4&ns=oWqcgbo-7-88Erb0vfdQlB0G&gir=yes&clen=39377316&ratebypass=yes&dur=579.012&lmt=1638885608167129&mt=1638913037&fvip=4&fexp=24001373%2C24007246&c=WEB&txp=3310222&n=RCgHqivzcADgV0inFcU&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Cgir%2Cclen%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRQIhAP5RM2aRT03WZPwBGRWRs25p6T03kecAfGoqqU1tQt0TAiAW-sbLCLqKm9XATrjmhgB5yIlGUeGF1WiWGWvFcVWgkA%3D%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRgIhAJNGheTpD9UVxle1Q9ECIhRMs7Cfl9ZZtqifKo81o-XRAiEAyYKhi3IBXMhIfPyvfpwmj069jMAhaxapC1IhDCl4k90%3D");

    assert(extractor.getURL(22) == "https://r4---sn-f5o5-jhol.googlevideo.com/videoplayback?expire=1638935038&ei=ntWvYYf_NZiJmLAPtfySkAc&ip=105.66.6.95&id=o-AG7BUTPMmXcFJCtiIUgzrYXlgliHnrjn8IT0b4D_2u8U&itag=22&source=youtube&requiressl=yes&mh=Zy&mm=31%2C29&mn=sn-f5o5-jhol%2Csn-h5qzen7s&ms=au%2Crdu&mv=m&mvi=4&pl=24&initcwndbps=112500&vprv=1&mime=video%2Fmp4&ns=oWqcgbo-7-88Erb0vfdQlB0G&cnr=14&ratebypass=yes&dur=579.012&lmt=1638885619798068&mt=1638913037&fvip=4&fexp=24001373%2C24007246&c=WEB&txp=3316222&n=RCgHqivzcADgV0inFcU&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Ccnr%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRQIhAJAAEjw50XBuXW4F5bLVKgzJQ-8HPiVFE9S94uknmEESAiBUZstN7FctoBLg25v5wJeJp5sNqlFziaYNcBdsJn3Feg%3D%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRgIhAJNGheTpD9UVxle1Q9ECIhRMs7Cfl9ZZtqifKo81o-XRAiEAyYKhi3IBXMhIfPyvfpwmj069jMAhaxapC1IhDCl4k90%3D");

    assert(extractor.getTitle() == "اللوبيا المغربية ديال دار سهلة و بنينة سخونة و حنينة");

    assert(extractor.getID() == "sif2JVDhZrQ");
}

unittest
{
    writeln("Should parse ID correctly (itemprop = 'identifier' version)".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    string html = readText("tests/identifier.html");
    auto extractor = new SimpleYoutubeVideoURLExtractor(html, new StdoutLogger());

    assert(extractor.getID() == "Q_-p2q5FHy0");
}

unittest
{
    import std.exception : collectExceptionMsg;
    writeln("Should gracefully fail for unplayable videos".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    string html = readText("tests/fgDQyFeBBIo.html");
    string exceptionMessage = collectExceptionMsg(new SimpleYoutubeVideoURLExtractor(html, new StdoutLogger()));
    string expectedExceptionMessage = "Video is unplayable because of status LOGIN_REQUIRED";
    assert(exceptionMessage == expectedExceptionMessage, "Expected message " ~ expectedExceptionMessage ~ " but got " ~ exceptionMessage);
}

enum AudioVisual : string
{
    AUDIO = "audio",
    VIDEO = "video"
};

struct YoutubeFormat
{
    int itag;
    ulong length;
    string quality;
    string mimetype;
    AudioVisual[] audioVisual;

    string extension() @property nothrow
    {
        auto slashIndex = mimetype.indexOf("/");
        auto semicolonIndex = mimetype.indexOf(";");
        if(slashIndex == -1 || semicolonIndex == -1 || slashIndex >= semicolonIndex)
        {
            return "mp4";
        }
        return mimetype[slashIndex + 1 .. semicolonIndex];
    }


    string toString()
    {
        string result = format!`[%d] (%s) %s MB %s`(
            itag,
            quality,
            length != 0 ? to!string(length / 1024.0 / 1024.0) : "unknown length",
            mimetype
        );
        if(audioVisual.length == 2)
        {
            return result;
        }
        return result ~ (audioVisual == [AudioVisual.AUDIO] ? " - audio only" : " - video only");
    }
}

unittest
{
    writeln("Should parse video formats".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    string html = readText("tests/zoz.html");
    auto extractor = new SimpleYoutubeVideoURLExtractor(html, new StdoutLogger());

    YoutubeFormat[] formats = extractor.getFormats();
    assert(formats.length == 18);

    assert(formats[0] == YoutubeFormat(18, 39377316, "360p", `video/mp4; codecs="avc1.42001E, mp4a.40.2"`, [AudioVisual.AUDIO, AudioVisual.VIDEO]));
    assert(formats[1] == YoutubeFormat(22, 0, "720p", `video/mp4; codecs="avc1.64001F, mp4a.40.2"`, [AudioVisual.AUDIO, AudioVisual.VIDEO]));
    assert(formats[2] == YoutubeFormat(137, 290388574, "1080p", `video/mp4; codecs="avc1.640028"`, [AudioVisual.VIDEO]));
    assert(formats[3] == YoutubeFormat(248, 150879241, "1080p", `video/webm; codecs="vp9"`, [AudioVisual.VIDEO]));
    assert(formats[4] == YoutubeFormat(136, 131812763, "720p", `video/mp4; codecs="avc1.64001f"`, [AudioVisual.VIDEO]));
    assert(formats[5] == YoutubeFormat(247, 84620239, "720p", `video/webm; codecs="vp9"`, [AudioVisual.VIDEO]));
    assert(formats[6] == YoutubeFormat(135, 65585157, "480p", `video/mp4; codecs="avc1.4d401e"`, [AudioVisual.VIDEO]));
    assert(formats[7] == YoutubeFormat(244, 43268080, "480p", `video/webm; codecs="vp9"`, [AudioVisual.VIDEO]));
    assert(formats[8] == YoutubeFormat(134, 32526895, "360p", `video/mp4; codecs="avc1.4d401e"`, [AudioVisual.VIDEO]));
    assert(formats[9] == YoutubeFormat(243, 24135571, "360p", `video/webm; codecs="vp9"`, [AudioVisual.VIDEO]));
    assert(formats[10] == YoutubeFormat(133, 15497476, "240p", `video/mp4; codecs="avc1.4d4015"`, [AudioVisual.VIDEO]));
    assert(formats[11] == YoutubeFormat(242, 13098616, "240p", `video/webm; codecs="vp9"`, [AudioVisual.VIDEO]));
    assert(formats[12] == YoutubeFormat(160, 6576387, "144p", `video/mp4; codecs="avc1.4d400c"`, [AudioVisual.VIDEO]));
    assert(formats[13] == YoutubeFormat(278, 6583212, "144p", `video/webm; codecs="vp9"`, [AudioVisual.VIDEO]));
    assert(formats[14] == YoutubeFormat(140, 9371359, "tiny", `audio/mp4; codecs="mp4a.40.2"`, [AudioVisual.AUDIO]));
    assert(formats[15] == YoutubeFormat(249, 3314860, "tiny", `audio/webm; codecs="opus"`, [AudioVisual.AUDIO]));
    assert(formats[16] == YoutubeFormat(250, 4347447, "tiny", `audio/webm; codecs="opus"`, [AudioVisual.AUDIO]));
    assert(formats[17] == YoutubeFormat(251, 8650557, "tiny", `audio/webm; codecs="opus"`, [AudioVisual.AUDIO]));

    assert(YoutubeFormat(278, 6583212, "144p", `video/webm; codecs="vp9"`, [AudioVisual.VIDEO]).extension == "webm");
    assert(YoutubeFormat(140, 9371359, "tiny", `audio/mp4; codecs="mp4a.40.2"`, [AudioVisual.AUDIO]).extension == "mp4");
    assert(YoutubeFormat(140, 9371359, "unknown", `foobar`, [AudioVisual.VIDEO]).extension == "mp4");
}

class AdvancedYoutubeVideoURLExtractor : YoutubeVideoURLExtractor
{
    private string baseJS;

    this(string html, string baseJS, StdoutLogger logger)
    {
        this.html = html;
        this.parser = createDocument(html);
        this.baseJS = baseJS;
        this.logger = logger;
        failIfUnplayable();
    }

    override string getURL(int itag, bool attemptDethrottle = false)
    {
        string signatureCipher = findSignatureCipher(itag);
        string[string] params = signatureCipher.parseQueryString();
        auto algorithm = EncryptionAlgorithm(baseJS, logger);
        string sig = algorithm.decrypt(params["s"]);
        string url = params["url"].decodeComponent() ~ "&" ~ params["sp"] ~ "=" ~ sig;

        string[string] urlParams = url.parseQueryString();
        if("n" !in urlParams || !attemptDethrottle)
        {
            return url;
        }

        string n = urlParams["n"];
        logger.displayVerbose("Found n : ", n);
        auto solver = ThrottlingAlgorithm(baseJS, logger);
        string solvedN = solver.solve(n);
        logger.displayVerbose("Solved n : ", solvedN);
        return url.replace("&n=" ~ n, "&n=" ~ solvedN);
    }

    override ulong findExpirationTimestamp(int itag)
    {
        string signatureCipher = findSignatureCipher(itag);
        string[string] params = signatureCipher.parseQueryString()["url"].decodeComponent().parseQueryString();
        return params["expire"].to!int;
    }

    string findSignatureCipher(int itag)
    {
        string encoded = "itag%3D" ~ itag.to!string;
        long index = html.indexOf(encoded);
        if(index == -1)
        {
            return "";
        }

        long startIndex = html[0 .. index].lastIndexOf("\"");
        if(startIndex == -1)
        {
            return "";
        }

        long endIndex = html[index .. $].indexOf("\"") + index;
        if(endIndex == -1)
        {
            return "";
        }
        return html[startIndex + 1 .. endIndex].replace(`\u0026`, "&");
    }

}

unittest
{
    writeln("Should parse video formats from VEVO videos".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    string html = readText("tests/dQ.html");
    auto extractor = new AdvancedYoutubeVideoURLExtractor(html, "", new StdoutLogger());

    YoutubeFormat[] formats = extractor.getFormats();
    assert(formats.length == 23);

    assert(formats[0] == YoutubeFormat(18, 0, "360p", `video/mp4; codecs="avc1.42001E, mp4a.40.2"`, [AudioVisual.AUDIO, AudioVisual.VIDEO]));
    assert(formats[1] == YoutubeFormat(137, 78662712, "1080p", `video/mp4; codecs="avc1.640028"`, [AudioVisual.VIDEO]));
    assert(formats[2] == YoutubeFormat(248, 55643203, "1080p", `video/webm; codecs="vp9"`, [AudioVisual.VIDEO]));
    assert(formats[3] == YoutubeFormat(399, 34279919, "1080p", `video/mp4; codecs="av01.0.08M.08"`, [AudioVisual.VIDEO]));
    assert(formats[4] == YoutubeFormat(136, 16598002, "720p", `video/mp4; codecs="avc1.4d401f"`, [AudioVisual.VIDEO]));
    assert(formats[5] == YoutubeFormat(247, 17149834, "720p", `video/webm; codecs="vp9"`, [AudioVisual.VIDEO]));
    assert(formats[6] == YoutubeFormat(398, 19086092, "720p", `video/mp4; codecs="av01.0.05M.08"`, [AudioVisual.VIDEO]));
    assert(formats[7] == YoutubeFormat(135, 8648011, "480p", `video/mp4; codecs="avc1.4d401e"`, [AudioVisual.VIDEO]));
    assert(formats[8] == YoutubeFormat(244, 9767682, "480p", `video/webm; codecs="vp9"`, [AudioVisual.VIDEO]));
    assert(formats[9] == YoutubeFormat(397, 10609264, "480p", `video/mp4; codecs="av01.0.04M.08"`, [AudioVisual.VIDEO]));
    assert(formats[10] == YoutubeFormat(134, 5661008, "360p", `video/mp4; codecs="avc1.4d401e"`, [AudioVisual.VIDEO]));
    assert(formats[11] == YoutubeFormat(243, 6839345, "360p", `video/webm; codecs="vp9"`, [AudioVisual.VIDEO]));
    assert(formats[12] == YoutubeFormat(396, 5953258, "360p", `video/mp4; codecs="av01.0.01M.08"`, [AudioVisual.VIDEO]));
    assert(formats[13] == YoutubeFormat(133, 3013651, "240p", `video/mp4; codecs="avc1.4d4015"`, [AudioVisual.VIDEO]));
    assert(formats[14] == YoutubeFormat(242, 3896369, "240p", `video/webm; codecs="vp9"`, [AudioVisual.VIDEO]));
    assert(formats[15] == YoutubeFormat(395, 3198834, "240p", `video/mp4; codecs="av01.0.00M.08"`, [AudioVisual.VIDEO]));
    assert(formats[16] == YoutubeFormat(160, 1859270, "144p", `video/mp4; codecs="avc1.4d400c"`, [AudioVisual.VIDEO]));
    assert(formats[17] == YoutubeFormat(278, 2157715, "144p", `video/webm; codecs="vp9"`, [AudioVisual.VIDEO]));
    assert(formats[18] == YoutubeFormat(394, 1502336, "144p", `video/mp4; codecs="av01.0.00M.08"`, [AudioVisual.VIDEO]));
    assert(formats[19] == YoutubeFormat(140, 3433514, "tiny", `audio/mp4; codecs="mp4a.40.2"`, [AudioVisual.AUDIO]));
    assert(formats[20] == YoutubeFormat(249, 1232413, "tiny", `audio/webm; codecs="opus"`, [AudioVisual.AUDIO]));
    assert(formats[21] == YoutubeFormat(250, 1630086, "tiny", `audio/webm; codecs="opus"`, [AudioVisual.AUDIO]));
    assert(formats[22] == YoutubeFormat(251, 3437753, "tiny", `audio/webm; codecs="opus"`, [AudioVisual.AUDIO]));

    html = readText("tests/dQ-adaptiveFormats-only.html");
    extractor = new AdvancedYoutubeVideoURLExtractor(html, "", new StdoutLogger());
    assert(!extractor.getFormats().canFind!(f => f.itag == 18));
}


unittest
{
    writeln("Should parse video URL and metadata from VEVO videos".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    string html = readText("tests/dQ.html");
    string baseJS = readText("tests/base.min.js");
    auto extractor = new AdvancedYoutubeVideoURLExtractor(html, baseJS, new StdoutLogger());

    assert(extractor.getID() == "dQw4w9WgXcQ");
    assert(extractor.getTitle() == "Rick Astley - Never Gonna Give You Up (Official Music Video)");

    assert(extractor.findSignatureCipher(18) == "s=%3D%3DQWEzyqIx3ngTN5fz-sonSUm8nJo9XPg0EEqYfnUgQgOBiAI4QV71XuujZ7Zn_YMeTTjj3R1ox9DGiAtIl5PS3xBeKAhIQRw8JQ0qO4O4\u0026sp=sig\u0026url=https://rr3---sn-f5o5-g53e.googlevideo.com/videoplayback%3Fexpire%3D1679282494%26ei%3D3nwXZLInx-RZrbOZgA4%26ip%3D105.67.131.46%26id%3Do-ADzvIi5vgKWgJk-TRxmT6ksUk64mzkUfV-JkvfCVFcLX%26itag%3D18%26source%3Dyoutube%26requiressl%3Dyes%26mh%3D7c%26mm%3D31%252C29%26mn%3Dsn-f5o5-g53e%252Csn-h5qzen7d%26ms%3Dau%252Crdu%26mv%3Dm%26mvi%3D3%26pl%3D24%26initcwndbps%3D132500%26vprv%3D1%26mime%3Dvideo%252Fmp4%26ns%3DN0utzYASQy85glQUKihYARgL%26cnr%3D14%26ratebypass%3Dyes%26dur%3D212.091%26lmt%3D1674233743350828%26mt%3D1679260398%26fvip%3D4%26fexp%3D24007246%26c%3DWEB%26txp%3D4530434%26n%3Dy1f34tdLpsslBu%26sparams%3Dexpire%252Cei%252Cip%252Cid%252Citag%252Csource%252Crequiressl%252Cvprv%252Cmime%252Cns%252Ccnr%252Cratebypass%252Cdur%252Clmt%26lsparams%3Dmh%252Cmm%252Cmn%252Cms%252Cmv%252Cmvi%252Cpl%252Cinitcwndbps%26lsig%3DAG3C_xAwRQIgSCCisEfk5u8_8dBiEjrMAGwGCR0D9yiB2-YiyAAizMACIQD06E3GivtKMmTc-NRuqj6zQbdyfAPxhhUEDZdSg17MkQ%253D%253D");

    assert(extractor.findSignatureCipher(396) == "s=8019W1vNihBw77R7UYPsFG2ap5YLMf1NEASbuqfoQ7DICAgRsJioiZ4T-xS_XxVc4O-uLTjkxB6AeJx97BMkGuFHgIARw8JQ0qO4O4\u0026sp=sig\u0026url=https://rr3---sn-f5o5-g53e.googlevideo.com/videoplayback%3Fexpire%3D1679282494%26ei%3D3nwXZLInx-RZrbOZgA4%26ip%3D105.67.131.46%26id%3Do-ADzvIi5vgKWgJk-TRxmT6ksUk64mzkUfV-JkvfCVFcLX%26itag%3D396%26aitags%3D133%252C134%252C135%252C136%252C137%252C160%252C242%252C243%252C244%252C247%252C248%252C278%252C394%252C395%252C396%252C397%252C398%252C399%26source%3Dyoutube%26requiressl%3Dyes%26mh%3D7c%26mm%3D31%252C29%26mn%3Dsn-f5o5-g53e%252Csn-h5qzen7d%26ms%3Dau%252Crdu%26mv%3Dm%26mvi%3D3%26pl%3D24%26initcwndbps%3D132500%26vprv%3D1%26mime%3Dvideo%252Fmp4%26ns%3DkwEoGNG1jfCHjoMtHo9a3wwL%26gir%3Dyes%26clen%3D5953258%26dur%3D212.040%26lmt%3D1674230525337110%26mt%3D1679260398%26fvip%3D4%26keepalive%3Dyes%26fexp%3D24007246%26c%3DWEB%26txp%3D4537434%26n%3DbWZ8RVMniF-UES%26sparams%3Dexpire%252Cei%252Cip%252Cid%252Caitags%252Csource%252Crequiressl%252Cvprv%252Cmime%252Cns%252Cgir%252Cclen%252Cdur%252Clmt%26lsparams%3Dmh%252Cmm%252Cmn%252Cms%252Cmv%252Cmvi%252Cpl%252Cinitcwndbps%26lsig%3DAG3C_xAwRAIgAMQ1ihzvXdU3bXepnUqzMvjZ31CVR1OJH5lR3xnHUu8CIHCjkIgGlAmEN-YsI5m1WZ-FwATK3CNhr3b1EYRTaKo3");

    assert(extractor.getURL(18) == "https://rr3---sn-f5o5-g53e.googlevideo.com/videoplayback?expire=1679282494&ei=3nwXZLInx-RZrbOZgA4&ip=105.67.131.46&id=o-ADzvIi5vgKWgJk-TRxmT6ksUk64mzkUfV-JkvfCVFcLX&itag=18&source=youtube&requiressl=yes&mh=7c&mm=31%2C29&mn=sn-f5o5-g53e%2Csn-h5qzen7d&ms=au%2Crdu&mv=m&mvi=3&pl=24&initcwndbps=132500&vprv=1&mime=video%2Fmp4&ns=N0utzYASQy85glQUKihYARgL&cnr=14&ratebypass=yes&dur=212.091&lmt=1674233743350828&mt=1679260398&fvip=4&fexp=24007246&c=WEB&txp=4530434&n=y1f34tdLpsslBu&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Ccnr%2Cratebypass%2Cdur%2Clmt&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRQIgSCCisEfk5u8_8dBiEjrMAGwGCR0D9yiB2-YiyAAizMACIQD06E3GivtKMmTc-NRuqj6zQbdyfAPxhhUEDZdSg17MkQ%3D%3D&sig=UO4Oq0QJ8wRQIhAKeBx3SP5lItAiGD9xo1R3jjTTeMY_nZ7ZjuuX17VQ4IAiBOgQg4nfYqEE0gPX9oJn8mUSnos-%3Df5NTgn3xIqyzEWQ%3D");

    assert(extractor.getURL(396) == "https://rr3---sn-f5o5-g53e.googlevideo.com/videoplayback?expire=1679282494&ei=3nwXZLInx-RZrbOZgA4&ip=105.67.131.46&id=o-ADzvIi5vgKWgJk-TRxmT6ksUk64mzkUfV-JkvfCVFcLX&itag=396&aitags=133%2C134%2C135%2C136%2C137%2C160%2C242%2C243%2C244%2C247%2C248%2C278%2C394%2C395%2C396%2C397%2C398%2C399&source=youtube&requiressl=yes&mh=7c&mm=31%2C29&mn=sn-f5o5-g53e%2Csn-h5qzen7d&ms=au%2Crdu&mv=m&mvi=3&pl=24&initcwndbps=132500&vprv=1&mime=video%2Fmp4&ns=kwEoGNG1jfCHjoMtHo9a3wwL&gir=yes&clen=5953258&dur=212.040&lmt=1674230525337110&mt=1679260398&fvip=4&keepalive=yes&fexp=24007246&c=WEB&txp=4537434&n=bWZ8RVMniF-UES&sparams=expire%2Cei%2Cip%2Cid%2Caitags%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Cgir%2Cclen%2Cdur%2Clmt&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRAIgAMQ1ihzvXdU3bXepnUqzMvjZ31CVR1OJH5lR3xnHUu8CIHCjkIgGlAmEN-YsI5m1WZ-FwATK3CNhr3b1EYRTaKo3&sig=uO4Oq0QJ8wRAIgHFuGkMB79xJeA6BxkjTLu-O4cVxX_Sx-T4ZioiJsRgACID7Qofq4bSAEN1fMLY5pa2GFsP8U7R77wBhiNv1W910");
}

unittest
{
    writeln("Should parse video URL and metadata from VEVO videos with iOS mweb client".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    string html = readText("tests/dQw4w9WgXcQ-mweb.html");
    string baseJS = readText("tests/28f14d97-mweb.js");
    auto extractor = new AdvancedYoutubeVideoURLExtractor(html, baseJS, new StdoutLogger());

    assert(extractor.getID() == "dQw4w9WgXcQ");
    assert(extractor.getTitle() == "Rick Astley - Never Gonna Give You Up (Official Music Video)");

    string actual = extractor.getURL(18, true);
    string expected = "https://rr1---sn-f5o5-jhol.googlevideo.com/videoplayback?expire=1731477559&ei=1-szZ7WoFfzBmLAP1u2p0Qk&ip=105.66.6.233&id=o-AEIgOfHGkI-fXTH-2KEs-Na0RS_o_2dO5HPL4jPiOpTA&itag=18&source=youtube&requiressl=yes&xpc=EgVo2aDSNQ%3D%3D&met=1731455959%2C&mh=7c&mm=31%2C29&mn=sn-f5o5-jhol%2Csn-h5qzen7d&ms=au%2Crdu&mv=m&mvi=1&pl=24&rms=au%2Cau&initcwndbps=340000&bui=AQn3pFQRD6UEONxpMtwptRDH9UWbUmZzU92PKN5aSQN32_Z2fUNC4MgW3BcnnPD2mUHYNichQTJ45Sk3&spc=qtApATlplmnedCoPrEiEKhkvzjTXfVqGJ1K7ksgPTmtGl0SimkV-1NI_220GZ8w&vprv=1&svpuc=1&mime=video%2Fmp4&ns=KrfT2EKC5cx1mSVnPNOk4k8Q&rqh=1&cnr=14&ratebypass=yes&dur=212.091&lmt=1717051812678016&mt=1731455571&fvip=4&fexp=51299154%2C51312688%2C51326932&c=MWEB&sefc=1&txp=4538434&n=xzB66wJdQ76DIQ&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cxpc%2Cbui%2Cspc%2Cvprv%2Csvpuc%2Cmime%2Cns%2Crqh%2Ccnr%2Cratebypass%2Cdur%2Clmt&lsparams=met%2Cmh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Crms%2Cinitcwndbps&lsig=AGluJ3MwRQIgchTTEAqbG2HruzLKh_4RHgpQCMu_zZt36i4PO6jmyp4CIQCkxUdX0QEQSlIvLPd_u-nGrcYQmP3UlfIcvEF7CgxgIg%3D%3D&sig=AJfQdSswRQIhANNyxFQL5GdStTbtnoQjriHR11DojPVbYrjkWnUNmbbgAiBqAY0JAQi079nqygYufsAzzxMCSg2TTETtbKZBBAPScg%3D%3D";
    assert(actual == expected, "Expected " ~ expected ~ "\nBut received " ~ actual);

    actual = extractor.getURL(396, true);
    expected = "https://rr1---sn-f5o5-jhol.googlevideo.com/videoplayback?expire=1731477559&ei=1-szZ7WoFfzBmLAP1u2p0Qk&ip=105.66.6.233&id=o-AEIgOfHGkI-fXTH-2KEs-Na0RS_o_2dO5HPL4jPiOpTA&itag=396&aitags=133%2C134%2C135%2C136%2C137%2C160%2C242%2C243%2C244%2C247%2C248%2C278%2C394%2C395%2C396%2C397%2C398%2C399%2C597%2C598&source=youtube&requiressl=yes&xpc=EgVo2aDSNQ%3D%3D&met=1731455959%2C&mh=7c&mm=31%2C29&mn=sn-f5o5-jhol%2Csn-h5qzen7d&ms=au%2Crdu&mv=m&mvi=1&pl=24&rms=au%2Cau&initcwndbps=340000&bui=AQn3pFRddAkdx8J1YF-gzGXsSLJ8T9sxKLW5ttqePQpSkHD1MEfXOxGCUU5Meg3s5Y0WgLNaVCvWCEO3&spc=qtApATlqlmnedCoPrEiEKhkvzjTXfVqGJ1K7ksgPTmtGl0SimkV-1NI_210D&vprv=1&svpuc=1&mime=video%2Fmp4&ns=vDTOPzFfo0i0NFc4ZQZA4KsQ&rqh=1&gir=yes&clen=5083621&dur=212.040&lmt=1717048855386476&mt=1731455571&fvip=4&keepalive=yes&fexp=51299154%2C51312688%2C51326932&c=MWEB&sefc=1&txp=4537434&n=HWC7SQ_qss_Upg&sparams=expire%2Cei%2Cip%2Cid%2Caitags%2Csource%2Crequiressl%2Cxpc%2Cbui%2Cspc%2Cvprv%2Csvpuc%2Cmime%2Cns%2Crqh%2Cgir%2Cclen%2Cdur%2Clmt&lsparams=met%2Cmh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Crms%2Cinitcwndbps&lsig=AGluJ3MwRQIgchTTEAqbG2HruzLKh_4RHgpQCMu_zZt36i4PO6jmyp4CIQCkxUdX0QEQSlIvLPd_u-nGrcYQmP3UlfIcvEF7CgxgIg%3D%3D&sig=AJfQdSswRQIhAOtma5L9ftuQ-jW_TT6rJjSCogycrQHcFjMG8c5eef4-AiB1XDDRUtiWZ3nqOiKF5z4Mb1jdU6ZTiedpEDBpTp0n3A%3D%3D";
    assert(actual == expected, "Expected " ~ expected ~ "\nBut received " ~ actual);
}

YoutubeVideoURLExtractor makeParser(string html, StdoutLogger logger)
{
    return makeParser(html, baseJSURL => baseJSURL.get().idup, logger);
}

YoutubeVideoURLExtractor makeParser(string html, string delegate(string) performGETRequest, StdoutLogger logger)
{
    if(html.canFind("signatureCipher"))
    {
        string baseJSURL = html.parseBaseJSURL();
        logger.displayVerbose("Found base.js URL = ", baseJSURL);
        string baseJS = performGETRequest(baseJSURL);
        return new AdvancedYoutubeVideoURLExtractor(html, baseJS, logger);
    }
    return new SimpleYoutubeVideoURLExtractor(html, logger);
}

unittest
{
    writeln("When video is VEVO song, should create advanced parser".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    string html = "tests/dQ.html".readText();
    auto parser = makeParser(html, url => "", new StdoutLogger());
    assert(cast(AdvancedYoutubeVideoURLExtractor) parser);
    assert(!cast(SimpleYoutubeVideoURLExtractor) parser);
}

unittest
{
    writeln("When video regular should create simple parser".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    string html = "tests/zoz.html".readText();
    auto parser = makeParser(html, url => "", new StdoutLogger());
    assert(cast(SimpleYoutubeVideoURLExtractor) parser);
    assert(!cast(AdvancedYoutubeVideoURLExtractor) parser);
}

string parseBaseJSURL(string html)
{
    return "https://www.youtube.com" ~ html.matchOrFail!`jsUrl"*:\s*"(.*?)"`;
}

unittest
{
    writeln("Should parse base.js URL".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    assert("https://www.youtube.com/s/player/59acb1f3/player_ias.vflset/ar_EG/base.js" == "tests/dQ.html".readText().parseBaseJSURL());
    assert("https://www.youtube.com/s/player/7862ca1f/player_ias.vflset/ar_EG/base.js" == "tests/dQw4w9WgXcQ.html".readText().parseBaseJSURL());
}

struct EncryptionAlgorithm
{
    alias Step = Tuple!(string, ulong);

    string javascript;
    private StdoutLogger logger;
    string[string] obfuscatedStepFunctionNames;
    Step[] steps;

    this(string javascript, StdoutLogger logger)
    {
        this.javascript = javascript;
        this.logger = logger;

        //string algorithm = javascript.matchOrFail!(`\w=\w\.split\(""\);((.|\s)*?);return \w\.join\(""\)`, false);
        enum nonCapturingDelimiterGroup = `(?:""|.*\[\d+\])`; //empty string or pW[5]
        string algorithm = javascript.matchOrFail!(`.=.\.split\(` ~ nonCapturingDelimiterGroup ~ `\);(.*);return .\.join\(` ~ nonCapturingDelimiterGroup ~ `\)`, false);
        logger.displayVerbose("Matched algorithm = ", algorithm);
        string[] steps = algorithm.split(";");
        foreach(step; steps.map!strip)
        {
            string functionName = step[step.indexOf('.') + 1 .. step.indexOf('(')];
            ulong argument = step[step.indexOf(',') + 1 .. step.indexOf(')')].strip().to!ulong;
            this.steps ~= tuple(functionName, argument);
        }
        logger.displayVerbose("Parsed steps : ", this.steps);
        parseStepFunctionNames();
    }

    string decrypt(string signatureCipher)
    {
        char[] copy = signatureCipher.decodeComponent.dup;
        foreach(step; steps)
        {
            logger.displayVerbose(step);
            logger.displayVerbose(obfuscatedStepFunctionNames);
            logger.displayVerbose("before step = ", copy);
            switch(obfuscatedStepFunctionNames[step[0]])
            {
                case "flip":
                    flip(copy);
                break;

                case "swapFirstCharacterWith":
                    swapFirstCharacterWith(copy, step[1]);
                break;

                case "removeFromStart":
                    removeFromStart(copy, step[1]);
                break;

                default:
                    assert(0);
            }
            logger.displayVerbose("after step = ", copy);
        }
        return copy.encodeComponent.idup;
    }

    private void parseStepFunctionNames()
    {
        logger.displayVerbose("Attempting to match ", `([A-Za-z]{2}):function\(\w\)\{\w\.reverse\(\)\}`);
        //string flip = javascript.matchOrFail!(`([A-Za-z0-9]{2,}):function\(\w\)\{\w\.reverse\(\)\}`);
        string flip = javascript.matchOrFail!(`([A-Za-z0-9]{2,}):function\(.\)\{.\.reverse\(\)\}`);
        logger.displayVerbose("Matched flip = ", flip);

        logger.displayVerbose("Attempting to match removeFromStart ", `([A-Za-z]{2}):function\(\w\)\{\w\.reverse\(\)\}`);
        //string removeFromStart = javascript.matchOrFail!(`([A-Za-z0-9]{2,}):function\(\w,\w\)\{\w\.splice\(0,\w\)\}`);
        string removeFromStart = javascript.matchOrFail!(`([A-Za-z0-9]{2,}):function\(.,.\)\{.\.splice\(0,.\)\}`);
        logger.displayVerbose("Matched removeFromStart = ", removeFromStart);

        logger.displayVerbose("Attempting to match swapFirstCharacterWith ", `([A-Za-z]{2}):function\(\w\)\{\w\.reverse\(\)\}`);
        //string swapFirstCharacterWith = javascript.matchOrFail!(`([A-Za-z0-9]{2,}):function\(\w,\w\)\{var \w=\w\[0\];\w\[0\]=\w\[\w%\w\.length\];\w\[\w%\w\.length\]=\w\}`);
        string swapFirstCharacterWith = javascript.matchOrFail!(`([A-Za-z0-9]{2,}):function\(.,.\)\{var .=.\[0\];.\[0\]=.\[.%.\.length\];.\[.%.\.length\]=.\}`);
        logger.displayVerbose("Matched swapFirstCharacterWith = ", swapFirstCharacterWith);

        obfuscatedStepFunctionNames[flip] = "flip";
        obfuscatedStepFunctionNames[swapFirstCharacterWith] = "swapFirstCharacterWith";
        obfuscatedStepFunctionNames[removeFromStart] = "removeFromStart";
    }

    private void flip(ref char[] input)
    {
        input.reverse();
    }

    private void swapFirstCharacterWith(ref char[] input, ulong b)
    {
        char tmp = input[0];
        input[0] = input[b % input.length];
        input[b % input.length] = tmp;
    }

    private void removeFromStart(ref char[] input, ulong amount)
    {
        input = input[amount .. $];
    }
}

unittest
{
    writeln("When video is VEVO song, should correctly decrypt video signature".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = EncryptionAlgorithm("tests/base.min.js".readText(), new StdoutLogger());
    string signature = algorithm.decrypt("L%3D%3DgKKNERRt_lv67W%3DvA4fU6N2qzrARSUbfqeXlAL827irDQICgwCLRfLgHEW2t5_GLJtRC-yoiR8sy0JR-uqLLRJlLJbgIQRw8JQ0qO1");
    assert(signature == "AOq0QJ8wRQIgbJLlJRLLqu-RJ0ys8Rioy-CRtJLG_5t2WEHgLfRLCwgCIQDri728L1lXeqfbUSRArzq2N6Uf4AvLW76vl_tRRENKKg%3D%3D");
}

unittest
{
    writeln("When video is VEVO song and player is 5b77d519, should correctly decrypt video signature".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = EncryptionAlgorithm("tests/5b77d519.js".readText(), new StdoutLogger());
    string signature = algorithm.decrypt("AIr%3DIr%3DIrg5t2EOs4ZBPETDqTCNkf7vH5D1%3Dnyay7ljoINmBywAEiAOlwos8WCcqQKDOCA5XUorfTmIqe9Y4DYBnBw6MxbIuJAhIgRwsSdQfJJ");
    assert(signature == "AJfQdSswRgIhAJuIbxM6wBnBYD4Y9eqImTJroUX5fCODKQqcCW8sowlOAiEAwyBmNIojl7yaynA1D5Hv7fkNCTqDTEPBZ4sOE2t5grI%3D");
}

unittest
{
    writeln("When video is VEVO song and player is 643afba4, should correctly decrypt video signature".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = EncryptionAlgorithm("tests/643afba4.js".readText(), new StdoutLogger());
    string actual = algorithm.decrypt("wIeAIeWIevIn2qCF3o_-dozs4AsiBA2qLk65K_qk1af9RaMEP3WEiAhvX2Hr%3Ddmpe_hDeRkbByG0xMfsm3wZt_Hcevx5Cx4uJAhIgRwsSdQfJA");
    string expected = "AJfQdSswRgIhAJu4xC5xvecH_tZw3msfMx0GyBbkReDh_epmd2rH2XvhAiEA3PEMaR9fa1kq_K56kLqWwBisA4szod-_o3FCq2nIveI%3D";
    assert(actual == expected, expected ~ " != " ~ actual);
}

struct ThrottlingAlgorithm
{
    alias Step = Tuple!(string, ulong);

    string javascript;
    private StdoutLogger logger;

    this(string javascript, StdoutLogger logger)
    {
        this.javascript = javascript;
        this.logger = logger;
    }

    string findChallengeName()
    {
        return javascript.matchOrFail!(`(.{3})=function\(\w\)\{var \w=\w\.split`, false);
    }

    string findChallengeImplementation()
    {
        string challengeName = findChallengeName().escaper().to!string;
        logger.displayVerbose("challenge name : ", challengeName);
        return javascript.matchOrFail(challengeName ~ `=(function\(\w\)\{(.|\s)+?)\.join\(.*\)\};`).strip();
    }

    string findEarlyExitCondition(string implementation)
    {
        return implementation.matchOrFail(`(if\(typeof .*\)return .*;)`);
    }

    string findGlobalVariable(string javascript)
    {
        //currently defined at the start of the file, might change later though
        //using matchFirst instead of matchOrFail because old base.js files don't have it
        auto match = javascript.matchFirst(`'use strict';(var .*=.*\.split\(".*"\)),`);
        return match.empty ? "" : match[1];

    }

    string solve(string n)
    {
        duk_context *context = duk_create_heap_default();
        if(!context)
        {
            logger.display("Failed to create a Duktape heap.".formatError());
            return n;
        }

        scope(exit)
        {
            duk_destroy_heap(context);
        }

        try
        {
            string rawImplementation = findChallengeImplementation();
            string implementation = format!`var descramble = %s.join("")};`(rawImplementation);
            string globalVariable = findGlobalVariable(javascript);
            if(globalVariable != "")
            {
                implementation = globalVariable ~ ";" ~ implementation;
                logger.displayVerbose("Found global variable, defining it before implementation: " ~ globalVariable);
            }
            try
            {
                string earlyExitCondition = findEarlyExitCondition(rawImplementation);
                logger.displayVerbose("Found early exit condition (", earlyExitCondition, "), removing it");
                implementation = implementation.replace(earlyExitCondition, "");
            }
            catch(Exception e)
            {
                logger.displayVerbose("No exit condition detected, skipping replacement");
            }
            duk_peval_string(context, implementation.toStringz());
            duk_get_global_string(context, "descramble");
            duk_push_string(context, n.toStringz());
            if(duk_pcall(context, 1) != 0)
            {
                throw new Exception(duk_safe_to_string(context, -1).to!string);
            }

            string result = duk_get_string(context, -1).to!string;
            duk_pop(context);
            return result;
        }
        catch(Exception e)
        {
            logger.display(e.message.idup.formatWarning());
            logger.display("Failed to solve N parameter, downloads might be rate limited".formatWarning());
            logger.displayVerbose(e.info.to!string.formatWarning());
            return n;
        }
    }
}

unittest
{
    writeln("Should parse challenge".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = ThrottlingAlgorithm("tests/base.min.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "ima", algorithm.findChallengeName() ~ " != ima");

    string expected = "BXfVEoYTXMkKsg";
    string actual = algorithm.solve("TVXfDeJvgqqwQZo");

    assert(expected == actual, expected ~ " != " ~ actual);
}

unittest
{
    writeln("Should parse new challenge".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = ThrottlingAlgorithm("tests/717a6f94.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "bma", algorithm.findChallengeName() ~ " != bma");

    string expected = "vDwB7sNN_ZK_8w";
    string actual = algorithm.solve("kVFjC9ssz1cOv88r");

    assert(expected == actual, expected ~ " != " ~ actual);
}

unittest
{
    writeln("Should solve challenge with unusual characters in it".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = ThrottlingAlgorithm("tests/a960a0cb.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "$la", algorithm.findChallengeName() ~ " != $la");

    string expected = "CJ6mFweU_U3YMQ";
    string actual = algorithm.solve("lTCmja7irJFW2HwaD");

    assert(expected == actual, expected ~ " != " ~ actual);
}

unittest
{
    writeln("Should parse challenge in base.js 3bb1f723".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = ThrottlingAlgorithm("tests/3bb1f723.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "bE7", algorithm.findChallengeName() ~ " != bE7");

    string expected = "AV62lAMNaE7dFw";
    string actual = algorithm.solve("dQHBl4-fgbfRe1kiGG");

    assert(expected == actual, expected ~ " != " ~ actual);
}


unittest
{
    writeln("Should parse challenge in base.js 643afba4".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = ThrottlingAlgorithm("tests/643afba4.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "qce", algorithm.findChallengeName() ~ " != qce");

    string expected = "og_-7K1fQ-5hMQ";
    string actual = algorithm.solve("So7m-jC7RrxI3eRZ");

    assert(expected == actual, expected ~ " != " ~ actual);
}
