import std.json;
import std.net.curl : get;
import std.stdio;
import std.typecons : Tuple;
import std.conv : to;
import std.array : replace;
import std.file : readText, writeText = write;
import std.string : indexOf, split, toStringz, join;
import std.regex : ctRegex, matchFirst, replaceAll, Captures;

import helpers : matchOrFail, StdoutLogger, formatTitle, formatSuccess, formatError, formatWarning;

import html;
import duktape;

enum JS_VARIABLE_REGEX_GROUP = `(\w|\$|_)+`;
enum JS_VARIABLE_REGEX_NON_CAPTURING_GROUP = `(?:\w+|\$|_)+`;

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
    }

    string findChallenge()
    {
        auto regexes = [
            //Nta(decodeURIComponent(h.s))
            ctRegex!`(\w+\(decodeURIComponent\(\w+?\.s\)\))`,
            //Fp(3,decodeURIComponent(P.s))
            ctRegex!`=((?:\w|_|\$)+?\(\d+?,decodeURIComponent\(\w+\.s\)\))`,
            //V0(b.url,b.sp,b.s)
            ctRegex!`((?:\w+?|\$|_)\((?:\w+?|\$|_)\.url,(?:\w+?|\$|_)\.sp,(?:\w+?|\$|_)\.s\))`,
        ];
        foreach(regex; regexes)
        {
            auto match = javascript.matchFirst(regex);
            if(!match.empty)
            {
               logger.displayVerbose("Found match: ", match[1]);
               return match[1];
            }
        }
        throw new Exception("Failed to find N param challenge name");
    }

    string injectFakes(string javascript)
    {
        return `var document = { }; var navigator = { }; 
        var WINDOW = {
                  "location": {
                            "hostname": ''
                          },
        };
        function XMLHttpRequest() { }` ~ javascript.replace("window.location.hostname", "WINDOW.location.hostname");
    }

    string injectDescrambleFunction(string javascript, string challengeName, string s)
    {
        return javascript.replace("})(_yt_player);", "descramble=" ~ challengeName ~ "})(_yt_player);") ~ "var descrambled = encodeURIComponent(descramble(decodeURIComponent('" ~ s ~ "')));";
    }

    string injectDescrambleFunction(string javascript, string challengeName, string firstArgument, string s)
    {
        return javascript.replace("})(_yt_player);", "descramble=" ~ challengeName ~ "})(_yt_player);") ~ "var descrambled = encodeURIComponent(descramble(" ~ firstArgument ~ ", decodeURIComponent('" ~ s ~ "')));";
    }

    string injectDescrambleFunctionWithEmptyArguments(string javascript, string challengeName, string s)
    {
        //this decrypting function returns an object where the signature is embedded in object.W.s
        //we don't know what W is ahead of time, so we traverse the object's keys
        //we have to pass in 's' as a second argument to the function so that the decrypted signature is found in object.W.s, not object.W.x for example
        //note: filtering with anonymous function because duktape doesn't support arrow functions ):
        return javascript.replace("})(_yt_player);", "descramble=" ~ challengeName ~ "})(_yt_player);") ~ "var result = descramble('', 's', '" ~ s ~ "'); var descrambled = Object.entries(result).filter(function(entry) { return entry[1] instanceof Object && entry[1].s !== undefined; })[0][1].s;";
    }

    string desugarReflectConstruct(string javascript)
    {
        //Reflect.construct(B,[],function(){});
        auto reflectConstructRegex = ctRegex!`Reflect.construct\(\w+?,\[\],function\(\)\{\}\)`;
        return javascript.replaceAll(reflectConstructRegex, "new function(){}");
    }

    string decrypt(string signatureCipher)
    {
        duk_context *context = duk_create_heap_default();
        if(!context)
        {
            logger.display("Failed to create a Duktape heap.".formatError());
            throw new Exception("Failed to decrypt signatureCipher");
        }

        scope(exit)
        {
            duk_destroy_heap(context);
        }

        try
        {
            string modifiedJavascript = injectFakes(javascript);
            modifiedJavascript = desugarReflectConstruct(modifiedJavascript);

            string challenge = findChallenge();
            string challengeName = challenge.matchOrFail!`((?:\w|_|\$)+?)\(.*?\)`;
            Captures!string optionalFirstArgument = challenge.matchFirst(ctRegex!`(?:\w|_|\$)+?\((\d+?),.*\)`);
            Captures!string optionalArgList = challenge.matchFirst(ctRegex!`(?:\w|_|\$)+?\((\w|\$|_)+?\.url,(\w|\$|_)+?\.sp,(\w|\$|_)+?\.s\)`);
            if(!optionalFirstArgument.empty)
            {
                modifiedJavascript = injectDescrambleFunction(modifiedJavascript, challengeName, optionalFirstArgument[1], signatureCipher);
            }
            else if(!optionalArgList.empty)
            {
                modifiedJavascript = injectDescrambleFunctionWithEmptyArguments(modifiedJavascript, challengeName, signatureCipher);
            }
            else
            {
                modifiedJavascript = injectDescrambleFunction(modifiedJavascript, challengeName, signatureCipher);
            }

            writeText("tmp2.js", modifiedJavascript);
            if(0 != duk_peval_string(context, modifiedJavascript.toStringz()))
            {
                throw new Exception(duk_safe_to_string(context, -1).to!string);
            }
            duk_get_global_string(context, "descrambled");
            string result = duk_get_string(context, -1).to!string;
            duk_pop(context);
            return result;
        }
        catch(Exception e)
        {
            logger.display(e.message.idup.formatWarning());
            logger.display("Failed to solve N parameter, downloads might be rate limited".formatWarning());
            logger.displayVerbose(e.info.to!string.formatWarning());
            return signatureCipher;
        }
    }

    string parseEncryptionObject(string encryptionFunctionBody)
    {
        //function starts with X=X.split("") and ends with return X.join("")
        //eg: r=r[Y[14]](Y[19]);oV[Y[8]](r,30);oV[Y[8]](r,65);oV[Y[8]](r,2);return r[Y[3]](Y[19])
        string[] steps = encryptionFunctionBody.split(";");
        string encryptionObject = steps[1].matchOrFail!`^(\w+?)`();
        return javascript.matchOrFail(`(var ` ~ encryptionObject ~ `=\{(?:.|\s)+?\}\});`);
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

unittest
{
    writeln("When video is VEVO song and player is 6450230e, should correctly decrypt video signature".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = EncryptionAlgorithm("tests/6450230e.js".readText(), new StdoutLogger());
    string actual = algorithm.decrypt("7JAQdSswRQIgTFkcmxRGlqPV7JpWHmq87SG4mDkD-dcSLKIcRReLNAMCIQCQv8fJjfJNNkIWlolE0fdqIc8EzfC__Yai7zM__GjMcA%3D%3D");
    string expected = "AJfQdSswRQIgTFkcmxRGlqPV7JpWHm787SG4mDkD-dcSLKIcRReLNAMCIQCQv8fJjqJNNkIWlolE0fdqIc8EzfC__Yai7zM__GjMcA%3D%3D";
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
        auto regexes = [
            ctRegex!(`(.{3})=function\(\w\)\{var \w=\w\.split`),

            //efh=function(r){var V=r[Y[14]](Y[19]),...return V[Y[3]](Y[19])};
            ctRegex!(`(\w{3})=function\(\w+?\)\{var \w+=\w\[.+\]\(.+\),(.|\s)+?return .+\(.+\)\};`),
            //$EK=function(p){var y=p[G[59]](G[11]),...return y[G[54]](G[11])};
            ctRegex!(`(.{3})=function\(\w+?\)\{var \w+=\w\[.+\]\(.+\),(.|\s)+?return .+\(.+\)\};`),
            ctRegex!(`var .{3}=\[(.{3})\]`),
            ctRegex!(`.\.url=(...)\(.\.url\)`),
        ];
        foreach(regex; regexes)
        {
            auto match = javascript.matchFirst(regex);
            if(!match.empty)
            {
               return match[1];
            }
        }
        throw new Exception("Failed to find N param challenge name");
    }

    string injectFakes(string javascript)
    {
        return `var document = { }; var navigator = { }; 
        var WINDOW = {
                  "location": {
                            "hostname": ''
                          },
        };
        function XMLHttpRequest() { }` ~ javascript.replace("window.location.hostname", "WINDOW.location.hostname");
    }

    string injectDescrambleFunction(string javascript, string challengeName, string n, string fakeUrl)
    {
        string argument = fakeUrl != "" ? fakeUrl : n;
        return javascript.replace("})(_yt_player);", "descramble=" ~ challengeName ~ "})(_yt_player);") ~ "var descrambled = descramble('" ~ argument ~ "');";
    }

    string desugarReflectConstruct(string javascript)
    {
        auto reflectConstructRegex = ctRegex!`Reflect.construct\(\w+?,\[\],function\(\)\{\}\)`;
        return javascript.replaceAll(reflectConstructRegex, "new function(){}");
    }

    string solve(string n, bool shouldFakeUrl = false)
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
            //99f55c01 expects N param to be passed as /n/XXXX, so we fabricate a minimal fake URL that satisfies the descrambling function's required format
            string[] fakeUrlParts = ["https://www.googlevideo.com/n/", n, "/videoplayback?n=" ~ n];

            string challengeName = findChallengeName();
            string modifiedJavascript = injectFakes(javascript);
            modifiedJavascript = desugarReflectConstruct(modifiedJavascript);
            modifiedJavascript = injectDescrambleFunction(modifiedJavascript, challengeName, n, shouldFakeUrl ? fakeUrlParts.join("") : "");
            writeText("tmp.js", modifiedJavascript);

            if(0 != duk_peval_string(context, modifiedJavascript.toStringz()))
            {
                throw new Exception(duk_safe_to_string(context, -1).to!string);
            }
            duk_get_global_string(context, "descrambled");
            string result = duk_get_string(context, -1).to!string;
            duk_pop(context);
            //99f55c01 expects N param to be passed as /n/XXXX and we injected it as such in injectDescrambleFunction
            //now we restore it by parsing it out of the fake URL
            return shouldFakeUrl ? result.replace(fakeUrlParts[0], "").replace(fakeUrlParts[2], "") : result;
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


unittest
{
    writeln("Should parse challenge in base.js 4fcd6e4a".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = ThrottlingAlgorithm("tests/4fcd6e4a.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "Frb", algorithm.findChallengeName() ~ " != Frb");

    string expected = "lG-0exgkM6bN-g";
    string actual = algorithm.solve("uj-MEVJQ7YTWzttOd");

    assert(expected == actual, expected ~ " != " ~ actual);
}

unittest
{
    writeln("Should parse challenge in base.js 6450230e".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = ThrottlingAlgorithm("tests/6450230e.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "efh", algorithm.findChallengeName() ~ " != efh");

    string expected = "Cn3MWNPkjgFyRg";
    string actual = algorithm.solve("G_lCLKGEWvaMaqex");

    assert(expected == actual, expected ~ " != " ~ actual);
}

unittest
{
    writeln("Should parse challenge in base.js 612f74a3.js".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = ThrottlingAlgorithm("tests/612f74a3.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "$EK", algorithm.findChallengeName() ~ " != $EK");

    string expected = "EQwmx-JXjcErOg";
    string actual = algorithm.solve("omEUhojTKoiJFceUf");

    assert(expected == actual, expected ~ " != " ~ actual);
}

unittest
{
    writeln("Should parse challenge in base.js a61444a1.js".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = ThrottlingAlgorithm("tests/a61444a1.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "wBF", algorithm.findChallengeName() ~ " != wBF");

    string expected = "COPjko6B96qp8w";
    string actual = algorithm.solve("f_sfmyVVVeUZxuvx");

    assert(expected == actual, expected ~ " != " ~ actual);
}

unittest
{
    writeln("When video is VEVO song, should correctly decrypt video signature".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = EncryptionAlgorithm("tests/29a37ef6.js".readText(), new StdoutLogger());

    string actual = algorithm.decrypt("wIeAIeWIevIn2qCF3o_-dozs4AsiBA2qLk65K_qk1af9RaMEP3WEiAhvX2Hr%3Ddmpe_hDeRkbByG0xMfsm3wZt_Hcevx5Cx4uJAhIgRwsSdQfJA");
    string expected = "iAIeWIevIn2qCF3o_-dozs4AskBA2qLk65K_qk1af9RaMEP3WEiAhvXHer%3Ddmpe_hDeR2bByG0xMfsm3wZt_Hcevx5Cx4uJAhIgRwsSdQfJA";

    assert(expected == actual, expected ~ " != " ~ actual);
}

unittest
{
    writeln("When video is VEVO song, should correctly decrypt video signature in base.js 8650557.js".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = EncryptionAlgorithm("tests/87644c66.js".readText(), new StdoutLogger());

    string actual = algorithm.decrypt("%3D%3DQZpiVjqkTmqUZtelcE3NAhh0Q5a0GMEYRcjhf_9SI_MDQICkMKZA5UNNKI-gNDNYOpWJlVASQtzLO3WVFexrbHS4qVgIQRwsSdQfJp");
    string expected = "AJfQdSswRQIgVqpSHbrxeFVW3OLztQSAVlJWpOYNDNg-IKNNU54ZKMkCIQDM_IS9_fhjcRYEMG0a5Q0hhAN3EcletZUqmTkqjVipZQ%3D%3D";

    assert(expected == actual, expected ~ " != " ~ actual);
}

unittest
{
    writeln("Should parse challenge in base.js 3062cec8.js".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = ThrottlingAlgorithm("tests/3062cec8.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "EuO", algorithm.findChallengeName() ~ " != EuO");

    string expected = "aXtqvScqyMQNhg";
    string actual = algorithm.solve("POgLT81CGkQw4dNl");

    assert(expected == actual, expected ~ " != " ~ actual);
}

unittest
{
    writeln("Should parse challenge in base.js 4e51e895.js".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = ThrottlingAlgorithm("tests/4e51e895.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "k90", algorithm.findChallengeName() ~ " != k90");

    string expected = "WOzMLbCkAi2gbQ";
    string actual = algorithm.solve("Bh4J-oo8NnHxOIsvX");

    assert(expected == actual, expected ~ " != " ~ actual);
}

unittest
{
    writeln("Should parse challenge in base.js 6c5cb4f4.js".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = ThrottlingAlgorithm("tests/6c5cb4f4.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "iaU", algorithm.findChallengeName() ~ " != iaU");

    string expected = "7QBqIDVmMRQMDQ";
    string actual = algorithm.solve("fuYjRvOmC35Q8SEA", true);

    assert(expected == actual, expected ~ " != " ~ actual);
}

unittest
{
    writeln("Should parse challenge in base.js 99f55c01.js".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = ThrottlingAlgorithm("tests/99f55c01.js".readText(), new StdoutLogger());
    assert(algorithm.findChallengeName() == "xFY", algorithm.findChallengeName() ~ " != xFY");

    string expected = "KenauEuQwP";
    string actual = algorithm.solve("VWfyv4PsZTsBGpID", true);

    assert(expected == actual, expected ~ " != " ~ actual);
}

unittest
{
    writeln("When video is VEVO song, should correctly decrypt video signature in base.js 6c5cb4f4.js".formatTitle());
    scope(success) writeln("OK\n".formatSuccess());
    auto algorithm = EncryptionAlgorithm("tests/6c5cb4f4.js".readText(), new StdoutLogger());

    string actual = algorithm.decrypt("D%3D6%3D%3DQxB7T%3D0HcDzEY48727NT1_zvKe3Rl7SW7jp6QHU0PXwDQICMv6sm66gRAu3n6x5BQxu-hYhQ4IRZ7LHkcrX5WQOEjWgIQRw4MNqEHn");
    string expected = "AHEqNM4wRQIgWjEOQW5XrckHL7ZRI4QhYh-uxQB5x6n3unRg6Dms6vMCIQDwXP0UHQ6pj7WS7lR3eKvz_1TN72784YEzDcH06T7BxQ%3D%3D";

    assert(expected == actual, expected ~ " != " ~ actual);
}
