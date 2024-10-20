import std.stdio : writef, stdout, writeln;
import std.algorithm : each;
import std.conv : to;
import std.string : format;
import std.file : getcwd, write, getSize;
import std.net.curl : get;
import std.path : buildPath;
import std.range : iota;
import std.logger;
import std.getopt;
import std.typecons : Yes, No;

import downloaders;
import helpers;
import parsers : makeParser, YoutubeFormat, YoutubeVideoURLExtractor, generateClientPlayerNonce;
import cache : Cache;

pragma(lib, "curl");

enum VERSION = "0.0.5";

version(linux)
{
    import core.sys.posix.signal;
    import core.stdc.stdio;

    extern(C) void signalHandler(int signal) nothrow @nogc
    {
        printf("Caught signal %d\n", signal);
    }
}

void main(string[] args)
{
    int itag = 18;
    bool displayFormats;
    bool parallel;
    bool outputURL;
    bool verbose;
    bool noProgress;
    bool noCache;
    bool dethrottle = true;
    bool chunked;
    bool displayVersion;
    string cookieFile;
    string poToken;

    version(linux)
    {
        signal(SIGPIPE, &signalHandler);
    }

    auto help = args.getopt(
        std.getopt.config.passThrough,
        std.getopt.config.caseSensitive,
        "f", "Format to download (see -F for available formats)", &itag,
        "F", "List available formats", &displayFormats,
        "o|output-url", "Display extracted video URL without downloading it", &outputURL,
        "p|parallel", "Download in 4 parallel connections", &parallel,
        "c|chunked", "Download in multiple serial chunks (experimental)", &chunked,
        "v|verbose", "Display debugging messages", &verbose,
        "no-progress", "Don't display real-time progress", &noProgress,
        "no-cache", "Skip caching of HTML and base.js", &noCache,
        "d|dethrottle", "Attempt to dethrottle download speed by solving the N challenge (defaults to true) (deprecated, will be removed soon)", &dethrottle,
        "no-dethrottle", "Skip N-challenge dethrottling attempt (deprecated, will be removed soon)", () { dethrottle = false; },
        "version", "Displays youtube-d version", &displayVersion,
        "cookiefile", "Cookie file, required for certain formats", &cookieFile,
        "potoken", "Proof of origin token, required for certain formats", &poToken
    );
    if(displayVersion)
    {
        VERSION.writeln();
        return;
    }

    if(help.helpWanted || args.length == 1)
    {
        defaultGetoptPrinter("Youtube downloader v" ~ VERSION, help.options);
        return;
    }

    writeln("Verbose mode : ", verbose);

    auto logger = new StdoutLogger(verbose);
    string[] urls = args[1 .. $];
    int retries = 2;

    foreach(url; urls)
    {
        foreach(retry; 0 .. retries)
        {
            try
            {
                handleURL(
                    url,
                    itag,
                    logger,
                    displayFormats,
                    outputURL,
                    parallel,
                    noProgress,
                    retry > 0 ? true : noCache, //force cache refresh on failure,
                    dethrottle,
                    chunked,
                    cookieFile,
                    poToken
                );
                break;
            }
            catch(Exception e)
            {
                logger.error(formatError(e.message.idup));
                logger.displayVerbose(e.info);
                logger.error("Retry ", retry + 1, " of ", retries);
                continue;
            }
            finally
            {
                logger.display("");
                logger.display("");
            }
        }
    }
}

void handleURL(string url, int itag, StdoutLogger logger, bool displayFormats, bool outputURL, bool parallel, bool noProgress, bool noCache, bool dethrottle, bool chunked, string cookieFile, string poToken)
{
    logger.display(formatTitle("Handling " ~ url));
    YoutubeVideoURLExtractor parser = Cache(logger, cookieFile, poToken, generateClientPlayerNonce(), noCache ? Yes.forceRefresh : No.forceRefresh).makeParser(url, itag);
    logger.displayVerbose("Downloaded video HTML");
    logger.displayVerbose("Attempt to dethrottle : " ~ (dethrottle ? "Yes" : "No"));
    if(!dethrottle)
    {
        logger.display("Dethrottling is now mandatory, the --no-dethrottle flag will be removed soon".formatWarning());
    }

    if(displayFormats)
    {
        logger.display("Available formats for ", url);
        parser.getFormats().each!(format => logger.display(format));
        logger.display();
        return;
    }

    logger.display(parser.getTitle());
    YoutubeFormat youtubeFormat = parser.getFormat(itag);
    string filename = format!"%s-%s-%d.%s"(parser.getTitle(), parser.getID(), itag, youtubeFormat.extension).sanitizePath();
    logger.displayVerbose(filename);
    string destination = buildPath(getcwd(), filename);
    logger.displayVerbose(destination);
    string link = parser.getURL(itag, dethrottle);

    logger.displayVerbose(parser.getID() ~ ".html");
    logger.displayVerbose("Found link : ", link);

    if(link == "")
    {
        throw new Exception("Failed to parse video URL");
    }

    if(outputURL)
    {
        logger.display(link);
        return;
    }

    logger.display("Downloading ", url, " to ", filename);

    Downloader downloader;
    if(parallel)
    {
        logger.display("Using ParallelDownloader");
        downloader = new ParallelDownloader(logger, parser.getID(), parser.getTitle(), youtubeFormat, !noProgress);
    }
    else if(chunked)
    {
        logger.display("Using ChunkedDownloader");
        logger.display("Warning: ChunkedDownloader is experimental".formatWarning());
        downloader = new ChunkedDownloader(logger, parser.getID(), parser.getTitle(), youtubeFormat, !noProgress);
    }
    else
    {
        logger.display("Using RegularDownloader");
        bool finished = false;
        downloader = new RegularDownloader(logger, youtubeFormat, (size_t total, size_t current) {
            if(current == 0 || total == 0 || finished)
            {
                return 0;
            }
            if(current == total)
            {
                logger.display("");
                logger.display("Done !".formatSuccess());
                finished = true;
                return 0;
            }
            auto percentage = 100.0 * (cast(float)(current) / total);
            writef!"\r[%.2f %%] %.2f / %.2f MB"(percentage, current / 1024.0 / 1024.0, total / 1024.0 / 1024.0);
            return 0;
        }, !noProgress);
    }
    downloader.download(destination, link, url);
}
