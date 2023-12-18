import std.json;
import std.net.curl : get;
import std.uri : decodeComponent, encodeComponent;
import std.stdio;
import std.typecons : tuple, Tuple;
import std.conv : to;
import std.array : replace;
import std.file : readText;
import std.string : indexOf, format, lastIndexOf, split, strip, toStringz;
import std.algorithm : canFind, filter, reverse, map;

import helpers : parseQueryString, matchOrFail, StdoutLogger, formatError;

import html;
import duktape;

abstract class YoutubeVideoURLExtractor
{
    protected string html;
    protected Document parser;

    abstract public string getURL(int itag = 18);
    abstract public ulong findExpirationTimestamp(int itag);

    public string getTitle()
    {
        return parser.querySelector("meta[name=title]").attr("content").idup;
    }

    public string getID()
    {
        auto meta = parser.querySelector("meta[itemprop=videoId]");
        if(meta is null)
        {
            meta = parser.querySelector("meta[itemprop=identifier]");
        }
        return meta.attr("content").idup;
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
        auto streamingData = html.matchOrFail!`"streamingData":(.*?),"player`;
        auto json = streamingData.parseJSON();
        YoutubeFormat[] formats;
        foreach(format; json[formatKey].array)
        {
            ulong contentLength = "contentLength" in format ? format["contentLength"].str.to!ulong : 0UL;
            string quality = "qualityLabel" in format ? format["qualityLabel"].str : format["quality"].str;
            formats ~= YoutubeFormat(
                cast(int) format["itag"].integer,
                contentLength,
                quality,
                format["mimeType"].str,
            );
        }
        return formats;
    }
}

class SimpleYoutubeVideoURLExtractor : YoutubeVideoURLExtractor
{
    private StdoutLogger logger;
    this(string html, StdoutLogger logger)
    {
        this.html = html;
        this.logger = logger;
        parser = createDocument(html);
    }

    override string getURL(int itag = 18)
    {
        return html
            .matchOrFail(`"itag":` ~ itag.to!string ~ `,"url":"(.*?)"`)
            .replace(`\u0026`, "&");
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
    writeln("Should parse video URL and metadata from regular videos");
    string html = readText("zoz.html");
    auto extractor = new SimpleYoutubeVideoURLExtractor(html, new StdoutLogger());

    assert(extractor.getURL(18) == "https://r4---sn-f5o5-jhol.googlevideo.com/videoplayback?expire=1638935038&ei=ntWvYYf_NZiJmLAPtfySkAc&ip=105.66.6.95&id=o-AG7BUTPMmXcFJCtiIUgzrYXlgliHnrjn8IT0b4D_2u8U&itag=18&source=youtube&requiressl=yes&mh=Zy&mm=31%2C29&mn=sn-f5o5-jhol%2Csn-h5qzen7s&ms=au%2Crdu&mv=m&mvi=4&pl=24&initcwndbps=112500&vprv=1&mime=video%2Fmp4&ns=oWqcgbo-7-88Erb0vfdQlB0G&gir=yes&clen=39377316&ratebypass=yes&dur=579.012&lmt=1638885608167129&mt=1638913037&fvip=4&fexp=24001373%2C24007246&c=WEB&txp=3310222&n=RCgHqivzcADgV0inFcU&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Cgir%2Cclen%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRQIhAP5RM2aRT03WZPwBGRWRs25p6T03kecAfGoqqU1tQt0TAiAW-sbLCLqKm9XATrjmhgB5yIlGUeGF1WiWGWvFcVWgkA%3D%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRgIhAJNGheTpD9UVxle1Q9ECIhRMs7Cfl9ZZtqifKo81o-XRAiEAyYKhi3IBXMhIfPyvfpwmj069jMAhaxapC1IhDCl4k90%3D");

    assert(extractor.getURL(22) == "https://r4---sn-f5o5-jhol.googlevideo.com/videoplayback?expire=1638935038&ei=ntWvYYf_NZiJmLAPtfySkAc&ip=105.66.6.95&id=o-AG7BUTPMmXcFJCtiIUgzrYXlgliHnrjn8IT0b4D_2u8U&itag=22&source=youtube&requiressl=yes&mh=Zy&mm=31%2C29&mn=sn-f5o5-jhol%2Csn-h5qzen7s&ms=au%2Crdu&mv=m&mvi=4&pl=24&initcwndbps=112500&vprv=1&mime=video%2Fmp4&ns=oWqcgbo-7-88Erb0vfdQlB0G&cnr=14&ratebypass=yes&dur=579.012&lmt=1638885619798068&mt=1638913037&fvip=4&fexp=24001373%2C24007246&c=WEB&txp=3316222&n=RCgHqivzcADgV0inFcU&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Ccnr%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRQIhAJAAEjw50XBuXW4F5bLVKgzJQ-8HPiVFE9S94uknmEESAiBUZstN7FctoBLg25v5wJeJp5sNqlFziaYNcBdsJn3Feg%3D%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRgIhAJNGheTpD9UVxle1Q9ECIhRMs7Cfl9ZZtqifKo81o-XRAiEAyYKhi3IBXMhIfPyvfpwmj069jMAhaxapC1IhDCl4k90%3D");

    assert(extractor.getTitle() == "اللوبيا المغربية ديال دار سهلة و بنينة سخونة و حنينة");

    assert(extractor.getID() == "sif2JVDhZrQ");
}

unittest
{
    writeln("Should parse ID correctly (itemprop = 'identifier' version)");
    string html = readText("identifier.html");
    auto extractor = new SimpleYoutubeVideoURLExtractor(html, new StdoutLogger());

    assert(extractor.getID() == "Q_-p2q5FHy0");
}

struct YoutubeFormat
{
    int itag;
    ulong length;
    string quality;
    string mimetype;

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
        return format!`[%d] (%s) %s MB %s`(
            itag,
            quality,
            length != 0 ? to!string(length / 1024.0 / 1024.0) : "unknown length",
            mimetype
        );
    }
}

unittest
{
    writeln("Should parse video formats");
    string html = readText("zoz.html");
    auto extractor = new SimpleYoutubeVideoURLExtractor(html, new StdoutLogger());

    YoutubeFormat[] formats = extractor.getFormats();
    assert(formats.length == 18);

    assert(formats[0] == YoutubeFormat(18, 39377316, "360p", `video/mp4; codecs="avc1.42001E, mp4a.40.2"`));
    assert(formats[1] == YoutubeFormat(22, 0, "720p", `video/mp4; codecs="avc1.64001F, mp4a.40.2"`));
    assert(formats[2] == YoutubeFormat(137, 290388574, "1080p", `video/mp4; codecs="avc1.640028"`));
    assert(formats[3] == YoutubeFormat(248, 150879241, "1080p", `video/webm; codecs="vp9"`));
    assert(formats[4] == YoutubeFormat(136, 131812763, "720p", `video/mp4; codecs="avc1.64001f"`));
    assert(formats[5] == YoutubeFormat(247, 84620239, "720p", `video/webm; codecs="vp9"`));
    assert(formats[6] == YoutubeFormat(135, 65585157, "480p", `video/mp4; codecs="avc1.4d401e"`));
    assert(formats[7] == YoutubeFormat(244, 43268080, "480p", `video/webm; codecs="vp9"`));
    assert(formats[8] == YoutubeFormat(134, 32526895, "360p", `video/mp4; codecs="avc1.4d401e"`));
    assert(formats[9] == YoutubeFormat(243, 24135571, "360p", `video/webm; codecs="vp9"`));
    assert(formats[10] == YoutubeFormat(133, 15497476, "240p", `video/mp4; codecs="avc1.4d4015"`));
    assert(formats[11] == YoutubeFormat(242, 13098616, "240p", `video/webm; codecs="vp9"`));
    assert(formats[12] == YoutubeFormat(160, 6576387, "144p", `video/mp4; codecs="avc1.4d400c"`));
    assert(formats[13] == YoutubeFormat(278, 6583212, "144p", `video/webm; codecs="vp9"`));
    assert(formats[14] == YoutubeFormat(140, 9371359, "tiny", `audio/mp4; codecs="mp4a.40.2"`));
    assert(formats[15] == YoutubeFormat(249, 3314860, "tiny", `audio/webm; codecs="opus"`));
    assert(formats[16] == YoutubeFormat(250, 4347447, "tiny", `audio/webm; codecs="opus"`));
    assert(formats[17] == YoutubeFormat(251, 8650557, "tiny", `audio/webm; codecs="opus"`));

    assert(YoutubeFormat(278, 6583212, "144p", `video/webm; codecs="vp9"`).extension == "webm");
    assert(YoutubeFormat(140, 9371359, "tiny", `audio/mp4; codecs="mp4a.40.2"`).extension == "mp4");
    assert(YoutubeFormat(140, 9371359, "unknown", `foobar`).extension == "mp4");
}

class AdvancedYoutubeVideoURLExtractor : YoutubeVideoURLExtractor
{
    private string baseJS;
    private StdoutLogger logger;

    this(string html, string baseJS, StdoutLogger logger)
    {
        this.html = html;
        this.parser = createDocument(html);
        this.baseJS = baseJS;
        this.logger = logger;
    }

    override string getURL(int itag = 18)
    {
        string signatureCipher = findSignatureCipher(itag);
        string[string] params = signatureCipher.parseQueryString();
        auto algorithm = EncryptionAlgorithm(baseJS, logger);
        string sig = algorithm.decrypt(params["s"]);
        return params["url"].decodeComponent() ~ "&" ~ params["sp"] ~ "=" ~ sig;
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
    writeln("Should parse video formats from VEVO videos");
    string html = readText("dQ.html");
    auto extractor = new AdvancedYoutubeVideoURLExtractor(html, "", new StdoutLogger());

    YoutubeFormat[] formats = extractor.getFormats();
    assert(formats.length == 23);

    assert(formats[0] == YoutubeFormat(18, 0, "360p", `video/mp4; codecs="avc1.42001E, mp4a.40.2"`));
    assert(formats[1] == YoutubeFormat(137, 78662712, "1080p", `video/mp4; codecs="avc1.640028"`));
    assert(formats[2] == YoutubeFormat(248, 55643203, "1080p", `video/webm; codecs="vp9"`));
    assert(formats[3] == YoutubeFormat(399, 34279919, "1080p", `video/mp4; codecs="av01.0.08M.08"`));
    assert(formats[4] == YoutubeFormat(136, 16598002, "720p", `video/mp4; codecs="avc1.4d401f"`));
    assert(formats[5] == YoutubeFormat(247, 17149834, "720p", `video/webm; codecs="vp9"`));
    assert(formats[6] == YoutubeFormat(398, 19086092, "720p", `video/mp4; codecs="av01.0.05M.08"`));
    assert(formats[7] == YoutubeFormat(135, 8648011, "480p", `video/mp4; codecs="avc1.4d401e"`));
    assert(formats[8] == YoutubeFormat(244, 9767682, "480p", `video/webm; codecs="vp9"`));
    assert(formats[9] == YoutubeFormat(397, 10609264, "480p", `video/mp4; codecs="av01.0.04M.08"`));
    assert(formats[10] == YoutubeFormat(134, 5661008, "360p", `video/mp4; codecs="avc1.4d401e"`));
    assert(formats[11] == YoutubeFormat(243, 6839345, "360p", `video/webm; codecs="vp9"`));
    assert(formats[12] == YoutubeFormat(396, 5953258, "360p", `video/mp4; codecs="av01.0.01M.08"`));
    assert(formats[13] == YoutubeFormat(133, 3013651, "240p", `video/mp4; codecs="avc1.4d4015"`));
    assert(formats[14] == YoutubeFormat(242, 3896369, "240p", `video/webm; codecs="vp9"`));
    assert(formats[15] == YoutubeFormat(395, 3198834, "240p", `video/mp4; codecs="av01.0.00M.08"`));
    assert(formats[16] == YoutubeFormat(160, 1859270, "144p", `video/mp4; codecs="avc1.4d400c"`));
    assert(formats[17] == YoutubeFormat(278, 2157715, "144p", `video/webm; codecs="vp9"`));
    assert(formats[18] == YoutubeFormat(394, 1502336, "144p", `video/mp4; codecs="av01.0.00M.08"`));
    assert(formats[19] == YoutubeFormat(140, 3433514, "tiny", `audio/mp4; codecs="mp4a.40.2"`));
    assert(formats[20] == YoutubeFormat(249, 1232413, "tiny", `audio/webm; codecs="opus"`));
    assert(formats[21] == YoutubeFormat(250, 1630086, "tiny", `audio/webm; codecs="opus"`));
    assert(formats[22] == YoutubeFormat(251, 3437753, "tiny", `audio/webm; codecs="opus"`));
}


unittest
{
    writeln("Should parse video URL and metadata from VEVO videos");
    string html = readText("dQw4w9WgXcQ.html");
    string baseJS = readText("base.min.js");
    auto extractor = new AdvancedYoutubeVideoURLExtractor(html, baseJS, new StdoutLogger());

    assert(extractor.getID() == "dQw4w9WgXcQ");
    assert(extractor.getTitle() == "Rick Astley - Never Gonna Give You Up (Official Music Video)");

    assert(extractor.findSignatureCipher(18) == "s=L%3D%3DgKKNERRt_lv67W%3DvA4fU6N2qzrARSUbfqeXlAL827irDQICgwCLRfLgHEW2t5_GLJtRC-yoiR8sy0JR-uqLLRJlLJbgIQRw8JQ0qO1&sp=sig&url=https://rr2---sn-f5o5-jhod.googlevideo.com/videoplayback%3Fexpire%3D1677997809%26ei%3DkeIDZIHQKMWC1ga62YWIDQ%26ip%3D105.66.0.249%26id%3Do-ADmt4SY6m6445pG7f4G5f72y1NE48ZiWiqWDA9pi6iQo%26itag%3D18%26source%3Dyoutube%26requiressl%3Dyes%26mh%3D7c%26mm%3D31%252C29%26mn%3Dsn-f5o5-jhod%252Csn-h5q7knes%26ms%3Dau%252Crdu%26mv%3Dm%26mvi%3D2%26pl%3D24%26initcwndbps%3D275000%26vprv%3D1%26mime%3Dvideo%252Fmp4%26ns%3DXFlGVko7q0z2CzI9Odw1BvcL%26cnr%3D14%26ratebypass%3Dyes%26dur%3D212.091%26lmt%3D1674233743350828%26mt%3D1677975897%26fvip%3D4%26fexp%3D24007246%26c%3DWEB%26txp%3D4530434%26n%3DTVXfDeJvgqqwQZo%26sparams%3Dexpire%252Cei%252Cip%252Cid%252Citag%252Csource%252Crequiressl%252Cvprv%252Cmime%252Cns%252Ccnr%252Cratebypass%252Cdur%252Clmt%26lsparams%3Dmh%252Cmm%252Cmn%252Cms%252Cmv%252Cmvi%252Cpl%252Cinitcwndbps%26lsig%3DAG3C_xAwRQIgZ_NXvvyuBRfcZ0Jmzc3UY0u4LlHk31riZU2FhqfFR7kCIQC62jB2OlVrTCZrSJ_itMUP5URwKclnuZXzkGCksV9I6g%253D%253D");

    assert(extractor.findSignatureCipher(396) == "s=P%3D%3DAi2cZ-qa3KUVLR%3D8ifB5eVi24LUAAtDJdrBXAwub3jYDQICwlGOfArS5Fk6UbM26kHntVmeswXUuJdXq2Rpv0rMIdagIQRw8JQ0qO7&sp=sig&url=https://rr2---sn-f5o5-jhod.googlevideo.com/videoplayback%3Fexpire%3D1677997809%26ei%3DkeIDZIHQKMWC1ga62YWIDQ%26ip%3D105.66.0.249%26id%3Do-ADmt4SY6m6445pG7f4G5f72y1NE48ZiWiqWDA9pi6iQo%26itag%3D396%26aitags%3D133%252C134%252C135%252C136%252C137%252C160%252C242%252C243%252C244%252C247%252C248%252C278%252C394%252C395%252C396%252C397%252C398%252C399%26source%3Dyoutube%26requiressl%3Dyes%26mh%3D7c%26mm%3D31%252C29%26mn%3Dsn-f5o5-jhod%252Csn-h5q7knes%26ms%3Dau%252Crdu%26mv%3Dm%26mvi%3D2%26pl%3D24%26initcwndbps%3D275000%26vprv%3D1%26mime%3Dvideo%252Fmp4%26ns%3DV1YGXTHGUU0a4PsRJqmYKX0L%26gir%3Dyes%26clen%3D5953258%26dur%3D212.040%26lmt%3D1674230525337110%26mt%3D1677975897%26fvip%3D4%26keepalive%3Dyes%26fexp%3D24007246%26c%3DWEB%26txp%3D4537434%26n%3DiRrA3X-4scFA5la%26sparams%3Dexpire%252Cei%252Cip%252Cid%252Caitags%252Csource%252Crequiressl%252Cvprv%252Cmime%252Cns%252Cgir%252Cclen%252Cdur%252Clmt%26lsparams%3Dmh%252Cmm%252Cmn%252Cms%252Cmv%252Cmvi%252Cpl%252Cinitcwndbps%26lsig%3DAG3C_xAwRQIgE-grPIIwKVqUa_siK-FtbLtMME0LPjp9rNlzuvLN7XQCIQCfVt03aw8T9cNgG3u_pFuQafSG4AQeKpgLEHcvodbUjA%253D%253D");

    assert(extractor.getURL(18) == "https://rr2---sn-f5o5-jhod.googlevideo.com/videoplayback?expire=1677997809&ei=keIDZIHQKMWC1ga62YWIDQ&ip=105.66.0.249&id=o-ADmt4SY6m6445pG7f4G5f72y1NE48ZiWiqWDA9pi6iQo&itag=18&source=youtube&requiressl=yes&mh=7c&mm=31%2C29&mn=sn-f5o5-jhod%2Csn-h5q7knes&ms=au%2Crdu&mv=m&mvi=2&pl=24&initcwndbps=275000&vprv=1&mime=video%2Fmp4&ns=XFlGVko7q0z2CzI9Odw1BvcL&cnr=14&ratebypass=yes&dur=212.091&lmt=1674233743350828&mt=1677975897&fvip=4&fexp=24007246&c=WEB&txp=4530434&n=TVXfDeJvgqqwQZo&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Ccnr%2Cratebypass%2Cdur%2Clmt&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRQIgZ_NXvvyuBRfcZ0Jmzc3UY0u4LlHk31riZU2FhqfFR7kCIQC62jB2OlVrTCZrSJ_itMUP5URwKclnuZXzkGCksV9I6g%3D%3D&sig=AOq0QJ8wRQIgbJLlJRLLqu-RJ0ys8Rioy-CRtJLG_5t2WEHgLfRLCwgCIQDri728L1lXeqfbUSRArzq2N6Uf4AvLW76vl_tRRENKKg%3D%3D");

    assert(extractor.getURL(396) == "https://rr2---sn-f5o5-jhod.googlevideo.com/videoplayback?expire=1677997809&ei=keIDZIHQKMWC1ga62YWIDQ&ip=105.66.0.249&id=o-ADmt4SY6m6445pG7f4G5f72y1NE48ZiWiqWDA9pi6iQo&itag=396&aitags=133%2C134%2C135%2C136%2C137%2C160%2C242%2C243%2C244%2C247%2C248%2C278%2C394%2C395%2C396%2C397%2C398%2C399&source=youtube&requiressl=yes&mh=7c&mm=31%2C29&mn=sn-f5o5-jhod%2Csn-h5q7knes&ms=au%2Crdu&mv=m&mvi=2&pl=24&initcwndbps=275000&vprv=1&mime=video%2Fmp4&ns=V1YGXTHGUU0a4PsRJqmYKX0L&gir=yes&clen=5953258&dur=212.040&lmt=1674230525337110&mt=1677975897&fvip=4&keepalive=yes&fexp=24007246&c=WEB&txp=4537434&n=iRrA3X-4scFA5la&sparams=expire%2Cei%2Cip%2Cid%2Caitags%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Cgir%2Cclen%2Cdur%2Clmt&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRQIgE-grPIIwKVqUa_siK-FtbLtMME0LPjp9rNlzuvLN7XQCIQCfVt03aw8T9cNgG3u_pFuQafSG4AQeKpgLEHcvodbUjA%3D%3D&sig=AOq0QJ8wRQIgadIMr0vpR2qXdJuUXwsemVtnHk62MbU6kF5SrAfOGlwCIQDYj3buw7XBrdJDtAAUL42iVe5Bfi8PRLVUK3aq-Zc2iA%3D%3D");
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
    writeln("When video is VEVO song, should create advanced parser");
    string html = "dQ.html".readText();
    auto parser = makeParser(html, url => "", new StdoutLogger());
    assert(cast(AdvancedYoutubeVideoURLExtractor) parser);
    assert(!cast(SimpleYoutubeVideoURLExtractor) parser);
}

unittest
{
    writeln("When video regular should create simple parser");
    string html = "zoz.html".readText();
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
    writeln("Should parse base.js URL");
    assert("https://www.youtube.com/s/player/59acb1f3/player_ias.vflset/ar_EG/base.js" == "dQ.html".readText().parseBaseJSURL());
    assert("https://www.youtube.com/s/player/7862ca1f/player_ias.vflset/ar_EG/base.js" == "dQw4w9WgXcQ.html".readText().parseBaseJSURL());
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

        string algorithm = javascript.matchOrFail!(`a\s*=\s*a\.split\(""\);\s*((.|\s)*?);\s*return a\.join\(""\)`, false);
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
        logger.displayVerbose("Attempting to match ", `([A-Za-z]{2}):function\(a\)\{a\.reverse\(\)\}`);
        string flip = javascript.matchOrFail!(`([A-Za-z0-9]{2,}):function\(a\)\{a\.reverse\(\)\}`);
        logger.displayVerbose("Matched flip = ", flip);

        logger.displayVerbose("Attempting to match removeFromStart ", `([A-Za-z]{2}):function\(a\)\{a\.reverse\(\)\}`);
        string removeFromStart = javascript.matchOrFail!(`([A-Za-z0-9]{2,}):function\(a,b\)\{a\.splice\(0,b\)\}`);
        logger.displayVerbose("Matched removeFromStart = ", removeFromStart);

        logger.displayVerbose("Attempting to match swapFirstCharacterWith ", `([A-Za-z]{2}):function\(a\)\{a\.reverse\(\)\}`);
        string swapFirstCharacterWith = javascript.matchOrFail!(`([A-Za-z0-9]{2,}):function\(a,b\)\{var c=a\[0\];a\[0\]=a\[b%a\.length\];a\[b%a\.length\]=c\}`);
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
    writeln("When video is VEVO song, should correctly decrypt video signature");
    auto algorithm = EncryptionAlgorithm("base.min.js".readText(), new StdoutLogger());
    string signature = algorithm.decrypt("L%3D%3DgKKNERRt_lv67W%3DvA4fU6N2qzrARSUbfqeXlAL827irDQICgwCLRfLgHEW2t5_GLJtRC-yoiR8sy0JR-uqLLRJlLJbgIQRw8JQ0qO1");
    assert(signature == "AOq0QJ8wRQIgbJLlJRLLqu-RJ0ys8Rioy-CRtJLG_5t2WEHgLfRLCwgCIQDri728L1lXeqfbUSRArzq2N6Uf4AvLW76vl_tRRENKKg%3D%3D");
}

struct ThrottlingAlgorithm
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
    }

    string findChallengeName()
    {
        return javascript.matchOrFail!(`\|\|([a-zA-Z]{3})\(""\)`, false);
    }

    string findChallengeImplementation()
    {
        string challengeName = findChallengeName();
        return javascript.matchOrFail(challengeName ~ `=function\(a\)\{((.|\s)+?)\};`).strip();
    }

    string solve(string n)
    {
        duk_context *ctx = duk_create_heap_default();
        if(!ctx)
        {
            logger.display("Failed to create a Duktape heap.");
            return n;
        }

        scope(exit)
        {
            duk_destroy_heap(ctx);
        }

        try
        {
            string implementation = format!`(function() {var a="%s";%s })()`(n, findChallengeImplementation());
            if(duk_peval_string(ctx, implementation.toStringz()) != 0)
            {
                writef("Error: %s\n", duk_safe_to_string(ctx, -1).to!string);
                return n;
            }

            string result = duk_get_string(ctx, -1).to!string;
            logger.display(result);
            return result;
        }
        catch(Exception e)
        {
            logger.display("Failed to solve N parameter, downloads might be rate limited".formatError());
            logger.display(e.message.idup.formatError());
            return n;
        }
    }
}

unittest
{
    writeln("Should parse challenge");
    auto algorithm = ThrottlingAlgorithm("base.min.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "ima", algorithm.findChallengeName() ~ " != ima");
    string actual = algorithm.findChallengeImplementation();
    string expected = `var b=a.split(""),c=[698401775,61910453,-404410333,function(){for(var d=64,e=[];++d-e.length-32;){switch(d){case 91:d=44;continue;case 123:d=65;break;case 65:d-=18;continue;case 58:d=96;continue;case 46:d=95}e.push(String.fromCharCode(d))}return e},
null,function(d,e){d.splice(d.length,0,e)},
-1887810242,-2024986974,859083917,1410296327,function(d){for(var e=d.length;e;)d.push(d.splice(--e,1)[0])},
function(){for(var d=64,e=[];++d-e.length-32;){switch(d){case 58:d-=14;case 91:case 92:case 93:continue;case 123:d=47;case 94:case 95:case 96:continue;case 46:d=95}e.push(String.fromCharCode(d))}return e},
-1035469155,1368647370,null,function(){for(var d=64,e=[];++d-e.length-32;)switch(d){case 58:d=96;continue;case 91:d=44;break;case 65:d=47;continue;case 46:d=153;case 123:d-=58;default:e.push(String.fromCharCode(d))}return e},
-45203544,887011725,1186206478,-775831027,1632754162,-307172264,1027311588,function(d,e){d=(d%e.length+e.length)%e.length;e.splice(-d).reverse().forEach(function(f){e.unshift(f)})},
b,function(d,e){for(e=(e%d.length+d.length)%d.length;e--;)d.unshift(d.pop())},
function(d,e,f,h,l){return e(f,h,l)},
428434598,-1949817253,2092756161,-2050932790,1454001343,784220257,-1963566458,1123017316,function(d,e){e=(e%d.length+d.length)%d.length;d.splice(e,1)},
1450591686,1968434056,-1391055614,"\u220e/",1016300989,",51];c[54]=c;","UDjUn",-666234774,-666234774,function(d,e){0!=d.length&&(e=(e%d.length+d.length)%d.length,d.splice(0,1,d.splice(e,1,d[0])[0]))},
-1189041180,1599508764,function(d,e,f,h,l,m,n,p,q){return f(h,l,m,n,p,q)},
function(d){d.reverse()},
712433312,2070384319,"hwadna7",-381860681,"(\\,][},",1935153521,function(d,e,f,h,l,m){return e(h,l,m)},
-800848978,-2050932790,function(d,e,f){var h=e.length;f.forEach(function(l,m,n){this.push(n[m]=e[(e.indexOf(l)-e.indexOf(this[m])+m+h--)%e.length])},d.split(""))},
function(){for(var d=64,e=[];++d-e.length-32;)switch(d){case 46:d=95;default:e.push(String.fromCharCode(d));case 94:case 95:case 96:break;case 123:d-=76;case 92:case 93:continue;case 58:d=44;case 91:}return e},
-1086585954,-336897119,-1198774214,-1700764381,-2033895861,-2140614363,1538172502,-1266939812,null,330905968,-372943234,1518927338,762033284,-826914387,1065513321,-1801395041,function(d,e){if(0!=d.length){e=(e%d.length+d.length)%d.length;var f=d[0];d[0]=d[e];d[e]=f}},
b,969944705,b,1071587255,-249313209];c[4]=c;c[14]=c;c[69]=c;try{try{-7!==c[79]&&(-3>=c[2]||((((0,c[23])(c[28],c[-100+Math.pow(4,5)%455]),c[59])(c[52],(0,c[3])(),c[78]),(0,c[Math.pow(1,5)%249- -44])(c[4],c[61])*(0,c[59])(c[42],(0,c[11])(),c[80]),c[59])(c[52],(0,c[3])(),c[24]),0))&&(0,c[26])((0,c[56])((0,c[45])(c[4],c[32]),c[10],(0,c[23])(c[-32465-Math.pow(6,3)+32753],c[4]),c[35])*(0,c[28])(c[61],c[47]),c[81],c[43],c[73]),7!=c[30]&&(0,c[17])((0,c[17])((0,c[20])(c[16],c[39]),c[72],c[32],c[81]),c[Math.pow(7,
2)-36-9],c[77],c[27]),5!=c[new Date("1970-01-01T04:31:01.000+04:30")/1E3]&&(2!=c[29]||((0,c[44])(c[79]),0))&&(0,c[68])(c[15],c[36])}catch(d){((0,c[34])(c[51],(0,c[78])(),c[69]),(0,c[34])(c[41],(0,c[33])(),c[69]),c[34])(c[51],(0,c[7])(),c[13])}try{(-1>c[30]||((0,c[58])(c[13],c[11]),0))&&(0,c[new Date("1970-01-01T10:01:10.000+10:00")/1E3])(c[74],c[79])}catch(d){(0,c[244*Math.pow(3,2)-2161])(c[15],c[72])}finally{-8!=c[49]&&(((0,c[3])((0,c[4])(c[25],c[50]),c[70- -1*Math.pow(1,1)],c[72],c[57]),c[53])(c[54],
c[62]),(0,c[36-Math.pow(6,4)- -1314])(c[40]))}try{9>=c[31]&&(0!==c[20]?(((0,c[70])(c[50],c[14]),c[29])(c[40],c[78]),c[29414+-47*Math.pow(5,4)])(c[64],c[77])<(0,c[-424+Math.pow(5,5)%449])(c[67],c[30]):((0,c[69])(c[33],c[76]),((0,c[55])(c[72],(0,c[27])(),c[33]),c[36])(c[35],c[1]),c[55])(c[72],(0,c[15])(),c[6])),10!=c[59]&&(9<=c[38]?(((0,c[4])(((((0,c[55])(c[62],(0,c[27])(),c[6]),c[7])(c[63],c[35]),c[new Date("1969-12-31T17:45:36.000-06:15")/1E3])(c[30],c[49]),c[7])(c[24],c[30]),c[5],c[16],c[21]),c[79])(c[33],
c[59]),(0,c[36])(c[30],c[47]),c[36+Math.pow(7,3)%60])(c[6],c[40]):((0,c[66])((0,c[20])(c[26]),((0,c[78])(c[53],c[60]),((0,c[10])(c[63],c[21300+Math.pow(7,3)+-21575]),c[65])(c[75],c[83]),c[12])(c[1],c[24]),c[77],(0,c[12])(c[55],c[69]),c[12],c[51],c[1]),c[76])(c[75],c[67])),(-4===c[81]||(((0,c[74])(c[47],c[48]),c[45])(c[48],c[31]),""))&&((0,c[45])(c[55],c[3]),c[76])(c[75],c[71]),c[36+Math.pow(6,1)%117]!==new Date("1969-12-31T22:45:00.000-01:15")/1E3&&(7<=c[17]&&(((((((0,c[45])(c[new Date("1970-01-01T02:46:15.000+02:45")/
1E3],c[49]),c[76])(c[46],c[10]),c[26])(c[Math.pow(2,2)+37312-37297],(0,c[27])(),c[46]),c[45])(c[48],c[52]),(0,c[16])(c[75]),c[23])((0,c[26])(c[9],(0,c[54])(),c[75]),c[new Date("1970-01-01T07:01:01.000+07:00")/1E3],(0,c[76])(c[48],c[35]),c[75]),c[23])((((0,c[16])(c[48]),c[74])(c[59],c[75]),c[74])(c[33],c[48]),c[16],(0,c[76])(c[46],c[72]),c[46]),[])||(0,c[77])((((((0,c[26])(c[9],(0,c[66])(),c[46]),((0,c[45])(c[48],c[42]),c[26])(c[19],(0,c[66])(),c[46])^(0,c[26])(c[9],(0,c[27])(),c[75]),c[2])(c[75],
c[82]),(0,c[26])(c[19],(0,c[66])(),c[46]),c[26])(c[9],(0,c[27])(),c[46]),c[23])((0,c[12])(c[46],c[81]),c[26],(0,c[45])(c[46],c[68]),c[19],(0,c[54])(),c[46]),c[77])((0,c[23092+Math.pow(2,new Date("1969-12-31T16:15:02.000-07:45")/1E3)+-23022])(c[53],c[46]),c[74],c[36],c[48]),c[26],c[19],(0,c[66])(),c[48]))}catch(d){(0,c[26])(c[19],(0,c[66])(),c[48]),(0,c[77])((0,c[2])(c[46],c[64]),c[61],c[46]),(0,c[12])(c[55],c[81*Math.pow(4,5)+-82931])}}catch(d){return"enhanced_except_2ZcBpuj-_w8_"+a}return b.join("")`;
    assert(actual == expected, actual ~ " != " ~ expected);

    expected = "BXfVEoYTXMkKsg";
    actual = algorithm.solve("TVXfDeJvgqqwQZo");

    assert(expected == actual, expected ~ " != " ~ actual);
}
