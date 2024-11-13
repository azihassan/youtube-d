import std.stdio : writef, writeln, File;
import std.parallelism : defaultPoolThreads, taskPool, totalCPUs;
import std.algorithm : each, sort, sum, map, min;
import std.conv : to;
import std.string : startsWith, indexOf, format, split;
import std.file : append, exists, read, remove, getSize;
import std.range : iota;
import std.net.curl : Curl, CurlOption, HTTP;
import std.math : ceil;
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
        auto http = HTTP(url);

        if(destination.exists)
        {
            ulong offset = destination.getSize();
            http.handle().set(CurlOption.resume_from, offset);
            logger.display("Resuming from byte ", offset);
        }
        else
        {
            http.addRequestHeader("Range", "bytes=0-");
            logger.display("Downloading from byte 0");
        }

        http.verbose(logger.verbose);
        auto curl = http.handle();
        ulong length = url.getContentLength();
        logger.displayVerbose("Length = ", length);
        if(destination.exists() && destination.getSize() == length)
        {
            logger.display("Done !".formatSuccess());
            return;
        }

        auto file = File(destination, "ab");
        curl.set(CurlOption.url, url);
        curl.set(CurlOption.useragent, "com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)");
        curl.set(CurlOption.referer, referer);
        curl.set(CurlOption.followlocation, true);
        curl.set(CurlOption.failonerror, true);
        curl.set(CurlOption.connecttimeout, 60 * 3);
        curl.set(CurlOption.nosignal, true);

        curl.onReceive = (ubyte[] data) {
            file.rawWrite(data);
            return data.length;
        };

        if(progress)
        {
            curl.onProgress = (size_t total, size_t current, size_t _, size_t __) {
                return onProgress(total, current);
            };
        }
        auto result = curl.perform();
    }
}

unittest
{
    import std.socket : Socket, TcpSocket, InternetAddress, SocketShutdown;
    import std.parallelism : task;
    import std.file : readText;

    writeln("Should include range header for new downloads");
    auto server = new TcpSocket();
    scope(exit)
    {
        server.shutdown(SocketShutdown.BOTH);
        server.close();
        "destination.mp4".exists() && "destination.mp4".remove();
    }
    server.bind(new InternetAddress("127.0.0.1", 1234));
    server.blocking = true;
    server.listen(1);

    task!(() {
        new RegularDownloader(new StdoutLogger(), (ulong length, ulong currentLength) { return 0; }).download(
                "destination.mp4",
                "http://127.0.0.1:1234/destination.mp4",
                "Random referer"
        );
    }).executeInNewThread();

    writeln("Awaiting connections...");
    auto client = server.accept();
    scope(exit) client.close();

    writeln("Client connected");
    auto rawRequest = new ubyte[8 * 1024]; //8 kb for good measure
    auto contentLength = client.receive(rawRequest);
    assert(contentLength != Socket.ERROR);

    string request = cast(string) rawRequest[0 .. contentLength];
    string response = "HTTP/1.1 200 OK\nContent-Length: 2\r\nContent-Type: video/mp4\r\n\r\nOK";

    //video length request, skipping checks
    if(request.startsWith("HEAD"))
    {
        assert(Socket.ERROR != client.send(response));
    }
    else
    {
        assert(request.indexOf("Range: bytes=0-") != 0);
        assert(Socket.ERROR != client.send(response));
        assert("destination.mp4".exists() && "destination.mp4".readText() == "OK");
    }
}

class ParallelDownloader : Downloader
{
    private StdoutLogger logger;
    private string id;
    private string title;
    private YoutubeFormat youtubeFormat;
    private bool progress;

    //open at most this many simultaneous connections to the youtube servers
    public int threadCount;

    //request range length limit above which youtube starts throttling downloads
    //https://github.com/azihassan/youtube-d/issues/65#issuecomment-2094993192
    public immutable LENGTH_THROTTLING_LIMIT = 10.0 * 1024.0 * 1024.0;

    this(StdoutLogger logger, string id, string title, YoutubeFormat youtubeFormat, bool progress = true)
    {
        this.id = id;
        this.title = title;
        this.logger = logger;
        this.youtubeFormat = youtubeFormat;
        this.progress = progress;
        this.threadCount = min(totalCPUs, 4);
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

        int chunks = cast(int) ceil(cast(double) length / LENGTH_THROTTLING_LIMIT);
        logger.displayVerbose(format!"Downloading %d chunks of %.2f MBs each across %d threads"(
            chunks,
            length / chunks / 1024.0 / 1024.0,
            threadCount
        ));
        string[] destinations = new string[chunks];
        defaultPoolThreads = threadCount;
        foreach(i, e; taskPool.parallel(iota(0, chunks)))
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

//experimental single-threaded parallel downloader for RegularDownloader doesn't cut it
//bypasses adaptive format rate limiting, but introduces a chunk concatenation step
//provided for convenience
class ChunkedDownloader : ParallelDownloader
{
    this(StdoutLogger logger, string id, string title, YoutubeFormat youtubeFormat, bool progress = true)
    {
        super(logger, id, title, youtubeFormat, progress);
        this.threadCount = 0;
    }
}

