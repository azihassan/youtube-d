import std.stdio : writef, writeln, File;
import std.parallelism : parallel;
import std.algorithm : each, sort, sum, map;
import std.conv : to;
import std.string : startsWith, indexOf, format, split;
import std.file : append, exists, read, remove, getSize;
import std.range : iota;
import std.net.curl : Curl, CurlOption;
import helpers : getContentLength, sanitizePath;

interface Downloader
{
    void download(string destination, string url, string referer);
}

class RegularDownloader : Downloader
{
    public void download(string destination, string url, string referer)
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
                    //info("Length = ", header["Content-Length:".length + 1 .. $]);
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
        //logMessage("cURL result = ", result);
    }
}

class ParallelDownloader : Downloader
{
    string id;
    string title;

    this(string id, string title)
    {
        this.id = id;
        this.title = title;
    }

    public void download(string destination, string url, string referer)
    {
        ulong length = url.getContentLength();
        writeln("Length = ", length);
        int chunks = 4;
        string[] destinations = new string[chunks];
        foreach(i, e; iota(0, chunks).parallel)
        {
            ulong[] offsets = calculateOffset(length, chunks, i);
            string partialLink = format!"%s&range=%d-%d"(url, offsets[0], offsets[1]);
            string partialDestination = format!"%s-%s-%d-%d.mp4.part.%d"(
                title, id, offsets[0], offsets[1], i
            ).sanitizePath();
            destinations[i] = partialDestination;
            new RegularDownloader().download(partialDestination, partialLink, url);
        }

        writeln("Chunk size sum : ", destinations.map!(d => d.getSize()).sum());
        writeln("Expected size : ", length);
        if(destinations.map!(d => d.getSize()).sum() == length)
        {
            writeln("Sizes match; concatenating files...");
            concatenateFiles(destinations, destination);
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
        auto downloader = new ParallelDownloader("", "");
        ulong length = 20 * 1024 * 1024;
        assert([0, 5 * 1024 * 1024] == downloader.calculateOffset(length, 4, 0));
        assert([5 * 1024 * 1024 + 1, 10 * 1024 * 1024] == downloader.calculateOffset(length, 4, 1));
        assert([10 * 1024 * 1024 + 1, 15 * 1024 * 1024] == downloader.calculateOffset(length, 4, 2));
        assert([15 * 1024 * 1024 + 1, 20 * 1024 * 1024] == downloader.calculateOffset(length, 4, 3));
    }

    unittest
    {
        auto downloader = new ParallelDownloader("", "");
        ulong length = 23;
        assert([0, 5] == downloader.calculateOffset(length, 4, 0));
        assert([5 + 1, 10] == downloader.calculateOffset(length, 4, 1));
        assert([10 + 1, 15] == downloader.calculateOffset(length, 4, 2));
        assert([15 + 1, 23] == downloader.calculateOffset(length, 4, 3));
    }
}
