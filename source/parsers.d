import std.json;
import std.uri : decodeComponent, encodeComponent;
import std.stdio;
import std.typecons : tuple, Tuple;
import std.regex : ctRegex, matchFirst, escaper;
import std.conv : to;
import std.array : replace;
import std.file : readText;
import std.string : indexOf, format, lastIndexOf, split, strip;
import std.algorithm : reverse, map;

import html;

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

struct AdvancedYoutubeVideoURLExtractor
{
    string html;
    string baseJS;
    private Document parser;

    this(string html, string baseJS)
    {
        this.html = html;
        this.baseJS = baseJS;
        parser = createDocument(html);
    }

    string getURL(int itag = 18)
    {
        string signatureCipher = findSignatureCipher(itag);
        string[string] params = signatureCipher.parseQueryString();
        auto algorithm = EncryptionAlgorithm(baseJS);
        string sig = algorithm.decrypt(params["s"]);
        return params["url"].decodeComponent() ~ "&" ~ params["sp"] ~ "=" ~ sig;
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
    string html = readText("dQw4w9WgXcQ.html");
    string baseJS = readText("base.min.js");
    auto extractor = AdvancedYoutubeVideoURLExtractor(html, baseJS);

    assert(extractor.getID() == "dQw4w9WgXcQ");
    assert(extractor.getTitle() == "Rick Astley - Never Gonna Give You Up (Official Music Video)");

    assert(extractor.findSignatureCipher(18) == "s=L%3D%3DgKKNERRt_lv67W%3DvA4fU6N2qzrARSUbfqeXlAL827irDQICgwCLRfLgHEW2t5_GLJtRC-yoiR8sy0JR-uqLLRJlLJbgIQRw8JQ0qO1&sp=sig&url=https://rr2---sn-f5o5-jhod.googlevideo.com/videoplayback%3Fexpire%3D1677997809%26ei%3DkeIDZIHQKMWC1ga62YWIDQ%26ip%3D105.66.0.249%26id%3Do-ADmt4SY6m6445pG7f4G5f72y1NE48ZiWiqWDA9pi6iQo%26itag%3D18%26source%3Dyoutube%26requiressl%3Dyes%26mh%3D7c%26mm%3D31%252C29%26mn%3Dsn-f5o5-jhod%252Csn-h5q7knes%26ms%3Dau%252Crdu%26mv%3Dm%26mvi%3D2%26pl%3D24%26initcwndbps%3D275000%26vprv%3D1%26mime%3Dvideo%252Fmp4%26ns%3DXFlGVko7q0z2CzI9Odw1BvcL%26cnr%3D14%26ratebypass%3Dyes%26dur%3D212.091%26lmt%3D1674233743350828%26mt%3D1677975897%26fvip%3D4%26fexp%3D24007246%26c%3DWEB%26txp%3D4530434%26n%3DTVXfDeJvgqqwQZo%26sparams%3Dexpire%252Cei%252Cip%252Cid%252Citag%252Csource%252Crequiressl%252Cvprv%252Cmime%252Cns%252Ccnr%252Cratebypass%252Cdur%252Clmt%26lsparams%3Dmh%252Cmm%252Cmn%252Cms%252Cmv%252Cmvi%252Cpl%252Cinitcwndbps%26lsig%3DAG3C_xAwRQIgZ_NXvvyuBRfcZ0Jmzc3UY0u4LlHk31riZU2FhqfFR7kCIQC62jB2OlVrTCZrSJ_itMUP5URwKclnuZXzkGCksV9I6g%253D%253D");

    assert(extractor.findSignatureCipher(396) == "s=P%3D%3DAi2cZ-qa3KUVLR%3D8ifB5eVi24LUAAtDJdrBXAwub3jYDQICwlGOfArS5Fk6UbM26kHntVmeswXUuJdXq2Rpv0rMIdagIQRw8JQ0qO7&sp=sig&url=https://rr2---sn-f5o5-jhod.googlevideo.com/videoplayback%3Fexpire%3D1677997809%26ei%3DkeIDZIHQKMWC1ga62YWIDQ%26ip%3D105.66.0.249%26id%3Do-ADmt4SY6m6445pG7f4G5f72y1NE48ZiWiqWDA9pi6iQo%26itag%3D396%26aitags%3D133%252C134%252C135%252C136%252C137%252C160%252C242%252C243%252C244%252C247%252C248%252C278%252C394%252C395%252C396%252C397%252C398%252C399%26source%3Dyoutube%26requiressl%3Dyes%26mh%3D7c%26mm%3D31%252C29%26mn%3Dsn-f5o5-jhod%252Csn-h5q7knes%26ms%3Dau%252Crdu%26mv%3Dm%26mvi%3D2%26pl%3D24%26initcwndbps%3D275000%26vprv%3D1%26mime%3Dvideo%252Fmp4%26ns%3DV1YGXTHGUU0a4PsRJqmYKX0L%26gir%3Dyes%26clen%3D5953258%26dur%3D212.040%26lmt%3D1674230525337110%26mt%3D1677975897%26fvip%3D4%26keepalive%3Dyes%26fexp%3D24007246%26c%3DWEB%26txp%3D4537434%26n%3DiRrA3X-4scFA5la%26sparams%3Dexpire%252Cei%252Cip%252Cid%252Caitags%252Csource%252Crequiressl%252Cvprv%252Cmime%252Cns%252Cgir%252Cclen%252Cdur%252Clmt%26lsparams%3Dmh%252Cmm%252Cmn%252Cms%252Cmv%252Cmvi%252Cpl%252Cinitcwndbps%26lsig%3DAG3C_xAwRQIgE-grPIIwKVqUa_siK-FtbLtMME0LPjp9rNlzuvLN7XQCIQCfVt03aw8T9cNgG3u_pFuQafSG4AQeKpgLEHcvodbUjA%253D%253D");

    assert(extractor.getURL(18) == "https://rr2---sn-f5o5-jhod.googlevideo.com/videoplayback?expire=1677997809&ei=keIDZIHQKMWC1ga62YWIDQ&ip=105.66.0.249&id=o-ADmt4SY6m6445pG7f4G5f72y1NE48ZiWiqWDA9pi6iQo&itag=18&source=youtube&requiressl=yes&mh=7c&mm=31%2C29&mn=sn-f5o5-jhod%2Csn-h5q7knes&ms=au%2Crdu&mv=m&mvi=2&pl=24&initcwndbps=275000&vprv=1&mime=video%2Fmp4&ns=XFlGVko7q0z2CzI9Odw1BvcL&cnr=14&ratebypass=yes&dur=212.091&lmt=1674233743350828&mt=1677975897&fvip=4&fexp=24007246&c=WEB&txp=4530434&n=TVXfDeJvgqqwQZo&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Ccnr%2Cratebypass%2Cdur%2Clmt&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRQIgZ_NXvvyuBRfcZ0Jmzc3UY0u4LlHk31riZU2FhqfFR7kCIQC62jB2OlVrTCZrSJ_itMUP5URwKclnuZXzkGCksV9I6g%3D%3D&sig=AOq0QJ8wRQIgbJLlJRLLqu-RJ0ys8Rioy-CRtJLG_5t2WEHgLfRLCwgCIQDri728L1lXeqfbUSRArzq2N6Uf4AvLW76vl_tRRENKKg%3D%3D");

    assert(extractor.getURL(396) == "https://rr2---sn-f5o5-jhod.googlevideo.com/videoplayback?expire=1677997809&ei=keIDZIHQKMWC1ga62YWIDQ&ip=105.66.0.249&id=o-ADmt4SY6m6445pG7f4G5f72y1NE48ZiWiqWDA9pi6iQo&itag=396&aitags=133%2C134%2C135%2C136%2C137%2C160%2C242%2C243%2C244%2C247%2C248%2C278%2C394%2C395%2C396%2C397%2C398%2C399&source=youtube&requiressl=yes&mh=7c&mm=31%2C29&mn=sn-f5o5-jhod%2Csn-h5q7knes&ms=au%2Crdu&mv=m&mvi=2&pl=24&initcwndbps=275000&vprv=1&mime=video%2Fmp4&ns=V1YGXTHGUU0a4PsRJqmYKX0L&gir=yes&clen=5953258&dur=212.040&lmt=1674230525337110&mt=1677975897&fvip=4&keepalive=yes&fexp=24007246&c=WEB&txp=4537434&n=iRrA3X-4scFA5la&sparams=expire%2Cei%2Cip%2Cid%2Caitags%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Cgir%2Cclen%2Cdur%2Clmt&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRQIgE-grPIIwKVqUa_siK-FtbLtMME0LPjp9rNlzuvLN7XQCIQCfVt03aw8T9cNgG3u_pFuQafSG4AQeKpgLEHcvodbUjA%3D%3D&sig=AOq0QJ8wRQIgadIMr0vpR2qXdJuUXwsemVtnHk62MbU6kF5SrAfOGlwCIQDYj3buw7XBrdJDtAAUL42iVe5Bfi8PRLVUK3aq-Zc2iA%3D%3D");
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

string parseBaseJSURL(string html)
{
    auto regex = ctRegex!`jsUrl"*:\s*"(.*?)"`;
    auto match = html.matchFirst(regex);
    if(match.empty)
    {
        return "";
    }
    return "https://www.youtube.com" ~ match[1];
}

unittest
{
    assert("https://www.youtube.com/s/player/59acb1f3/player_ias.vflset/ar_EG/base.js" == "dQ.html".readText().parseBaseJSURL());
    assert("https://www.youtube.com/s/player/7862ca1f/player_ias.vflset/ar_EG/base.js" == "dQw4w9WgXcQ.html".readText().parseBaseJSURL());
}

struct EncryptionAlgorithm
{
    alias Step = Tuple!(string, ulong);

    string javascript;
    string[string] obfuscatedStepFunctionNames;
    Step[] steps;

    this(string javascript)
    {
        this.javascript = javascript;

        string algorithm = matchOrFail!(`a\s*=\s*a\.split\(""\);\s*((.|\s)*?);\s*return a\.join\(""\)`, false);
        //writeln("Matched algorithm = ", algorithm);
        //writeln();
        string[] steps = algorithm.split(";");
        foreach(step; steps.map!strip)
        {
            string functionName = step[3 .. step.indexOf('(')];
            ulong argument = step[step.indexOf(',') + 1 .. step.indexOf(')')].strip().to!ulong;
            this.steps ~= tuple(functionName, argument);
        }
        //writeln("Parsed steps : ", this.steps);
        //writeln();
        parseStepFunctionNames();
    }

    string decrypt(string signatureCipher)
    {
        char[] copy = signatureCipher.decodeComponent.dup;
        foreach(step; steps)
        {
            //writeln(step);
            //writeln(obfuscatedStepFunctionNames);
            //writeln("before step = ", copy);
            //writeln();
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
            //writeln("after step = ", copy);
        }
        return copy.encodeComponent.idup;
    }

    private void parseStepFunctionNames()
    {
        string flip = matchOrFail!(`([A-Za-z]{2}):function\(a\)\{a\.reverse\(\)\}`);
        //writeln("Matched flip = ", flip);
        //writeln();

        string removeFromStart = matchOrFail!(`([A-Za-z]{2}):function\(a,b\)\{a\.splice\(0,b\)\}`);
        //writeln("Matched removeFromStart = ", removeFromStart);
        //writeln();

        string swapFirstCharacterWith = matchOrFail!(`([A-Za-z]{2}):function\(a,b\)\{var c=a\[0\];a\[0\]=a\[b%a\.length\];a\[b%a\.length\]=c\}`);
        //writeln("Matched swapFirstCharacterWith = ", swapFirstCharacterWith);
        //writeln();

        obfuscatedStepFunctionNames[flip] = "flip";
        obfuscatedStepFunctionNames[swapFirstCharacterWith] = "swapFirstCharacterWith";
        obfuscatedStepFunctionNames[removeFromStart] = "removeFromStart";
    }

    private string matchOrFail(string pattern, bool escape = false)()
    {
        //writeln("Matching ", escape ? pattern.escaper.to!string : pattern);
        //writeln();
        auto regex = ctRegex!(escape ? pattern.escaper.to!string : pattern);
        auto match = javascript.matchFirst(regex);
        //writeln(match);
        if(match.empty)
        {
            throw new Exception("Failed to parse encryption steps");
        }
        return match[1];
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
    auto algorithm = EncryptionAlgorithm("base.min.js".readText());
    string signature = algorithm.decrypt("L%3D%3DgKKNERRt_lv67W%3DvA4fU6N2qzrARSUbfqeXlAL827irDQICgwCLRfLgHEW2t5_GLJtRC-yoiR8sy0JR-uqLLRJlLJbgIQRw8JQ0qO1");

    //writeln("expected = AOq0QJ8wRQIgbJLlJRLLqu-RJ0ys8Rioy-CRtJLG_5t2WEHgLfRLCwgCIQDri728L1lXeqfbUSRArzq2N6Uf4AvLW76vl_tRRENKKg%3D%3D");
    //writeln("received = ", signature);
    assert(signature == "AOq0QJ8wRQIgbJLlJRLLqu-RJ0ys8Rioy-CRtJLG_5t2WEHgLfRLCwgCIQDri728L1lXeqfbUSRArzq2N6Uf4AvLW76vl_tRRENKKg%3D%3D");
}
