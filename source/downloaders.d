import std.stdio : writef, writeln, File;
import std.parallelism : parallel;
import std.algorithm : each, sort, sum, map;
import std.conv : to;
import std.string : startsWith, indexOf, format, split;
import std.file : append, exists, read, remove, getSize;
import std.range : iota;
import std.net.curl : Curl, CurlOption;
import helpers : getContentLength, sanitizePath, StdoutLogger, formatSuccess, formatTitle;

import parsers : YoutubeFormat;

interface Downloader
{
    void download(string destination, string url, string referer);
}

class RegularDownloader : Downloader
{
    private StdoutLogger logger;
    private int delegate(ulong length, ulong currentLength) onProgress;
    private bool progress;

    this(StdoutLogger logger, int delegate(ulong length, ulong currentLength) onProgress, bool progress = true)
    {
        this.logger = logger;
        this.onProgress = onProgress;
        this.progress = progress;
    }

    public void download(string destination, string url, string referer)
    {
        auto http = Curl();
        http.initialize();
        if(destination.exists)
        {
            logger.display("Resuming from byte ", destination.getSize());
            http.set(CurlOption.resume_from, destination.getSize());
        }

        ulong length = url.getContentLength();
        logger.displayVerbose("Length = ", length);
        if(destination.exists() && destination.getSize() == length)
        {
            logger.display("Done !".formatSuccess());
            return;
        }


        auto file = File(destination, "ab");
        http.set(CurlOption.url, url);
        http.set(CurlOption.useragent, "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:95.0) Gecko/20100101 Firefox/95.0");
        http.set(CurlOption.referer, referer);
        http.set(CurlOption.followlocation, true);
        http.set(CurlOption.failonerror, true);
        http.set(CurlOption.connecttimeout, 60 * 3);
        http.set(CurlOption.nosignal, true);

        http.onReceiveHeader = (in char[]  header) {
            logger.displayVerbose(header);
        };

        http.onReceive = (ubyte[] data) {
            file.rawWrite(data);
            return data.length;
        };

        if(progress)
        {
            http.onProgress = (size_t total, size_t current, size_t _, size_t __) {
                return onProgress(total, current);
            };
        }
        auto result = http.perform();
    }
}

class ParallelDownloader : Downloader
{
    private StdoutLogger logger;
    private string id;
    private string title;
    private YoutubeFormat youtubeFormat;
    private bool progress;

    this(StdoutLogger logger, string id, string title, YoutubeFormat youtubeFormat, bool progress = true)
    {
        this.id = id;
        this.title = title;
        this.logger = logger;
        this.youtubeFormat = youtubeFormat;
        this.progress = progress;
    }

    public void download(string destination, string url, string referer)
    {
        ulong length = url.getContentLength();
        logger.displayVerbose("Length = ", length);
        if(destination.exists() && destination.getSize() == length)
        {
            logger.display("Done !".formatSuccess());
            return;
        }

        int chunks = 4;
        string[] destinations = new string[chunks];
        foreach(i, e; iota(0, chunks).parallel)
        {
            ulong[] offsets = calculateOffset(length, chunks, i);
            string partialLink = format!"%s&range=%d-%d"(url, offsets[0], offsets[1]);
            string partialDestination = format!"%s-%s-%d-%d-%d.%s.part.%d"(
                title, id, youtubeFormat.itag, offsets[0], offsets[1], youtubeFormat.extension, i
            ).sanitizePath();
            destinations[i] = partialDestination;

            if(partialDestination.exists() && partialDestination.getSize() >= offsets[1] - offsets[0])
            {
                logger.displayVerbose(partialDestination, " already has ", partialDestination.getSize(), " bytes, skipping");
                continue;
            }
            new RegularDownloader(logger, (ulong _, ulong __) {
                if(length == 0)
                {
                    return 0;
                }
                ulong current = destinations.map!(d => d.exists() ? d.getSize() : 0).sum();
                auto percentage = 100.0 * (cast(float)(current) / length);
                writef!"\r[%.2f %%] %.2f / %.2f MB"(percentage, current / 1024.0 / 1024.0, length / 1024.0 / 1024.0);
                return 0;
            }, progress).download(partialDestination, partialLink, url);
        }

        writeln();
        logger.displayVerbose("Chunk size sum : ", destinations.map!(d => d.getSize()).sum());
        logger.displayVerbose("Expected size : ", length);
        if(destinations.map!(d => d.getSize()).sum() == length)
        {
            logger.display("Concatenating partial files...");
            concatenateFiles(destinations, destination);
            logger.display("Done !".formatSuccess());
        }
    }

    private void concatenateFiles(string[] files, string destination)
    {
        files.sort!((a, b) => a.split(".")[$ - 1].to!int < b.split(".")[$ -1].to!int);
        foreach(file; files)
        {
            destination.append(file.read());
        }
        files.each!remove;
    }

    private ulong[] calculateOffset(ulong length, int chunks, ulong index)
    {
        ulong start = index * (length / chunks);
        ulong end = chunks == index + 1 ? length : start + (length / chunks);
        if(index > 0)
        {
            start++;
        }
        return [start, end];
    }

    unittest
    {
        writeln("Should calculate offsets correctly");
        scope(success) writeln("OK\n".formatSuccess());
        auto downloader = new ParallelDownloader(new StdoutLogger(), "", "", YoutubeFormat(18, 9371359, "360p", "video/mp4"));
        ulong length = 20 * 1024 * 1024;
        assert([0, 5 * 1024 * 1024] == downloader.calculateOffset(length, 4, 0));
        assert([5 * 1024 * 1024 + 1, 10 * 1024 * 1024] == downloader.calculateOffset(length, 4, 1));
        assert([10 * 1024 * 1024 + 1, 15 * 1024 * 1024] == downloader.calculateOffset(length, 4, 2));
        assert([15 * 1024 * 1024 + 1, 20 * 1024 * 1024] == downloader.calculateOffset(length, 4, 3));
    }

    unittest
    {
        writeln("Should calculate offsets correctly");
        scope(success) writeln("OK\n".formatSuccess());
        auto downloader = new ParallelDownloader(new StdoutLogger(), "", "", YoutubeFormat(18, 9371359, "360p", "video/mp4"));
        ulong length = 23;
        assert([0, 5] == downloader.calculateOffset(length, 4, 0));
        assert([5 + 1, 10] == downloader.calculateOffset(length, 4, 1));
        assert([10 + 1, 15] == downloader.calculateOffset(length, 4, 2));
        assert([15 + 1, 23] == downloader.calculateOffset(length, 4, 3));
    }
}
