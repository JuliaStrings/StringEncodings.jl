using Base.Test
using Compat: readstring
using LegacyStrings: UTF8String, UTF16String, UTF32String
using StringEncodings

for s in ("", "\0", "a", "café crème",
          "a"^(StringEncodings.BUFSIZE-1) * "€ with an incomplete codepoint between two input buffer fills",
          "a string € チャネルパートナーの選択",
          "a string \0€ チャネルパ\0ー\0トナーの選択 with embedded and trailing nuls\0")
    # Test round-trip to Unicode formats, checking against pure-Julia implementation
    for (T, nullen) in ((UTF8String, 0), (UTF16String, 2), (UTF32String, 4))
        enc = StringEncodings.encoding(T)
        a = reinterpret(UInt8, T(s).data)
        # Adjust for explicit \0 only for .data on UTF16String/UTF32String
        a = a[1:end - nullen]
        @test decode(a, enc) == s
        @test decode(UTF16String, a, enc) == s
        @test decode(UTF32String, a, enc) == s
        @test decode(encode(s, enc), enc) == s
    end
end

# Test a few non-Unicode encodings
for (s, enc) in (("noël", "ISO-8859-1"),
                 ("noël €", "ISO-8859-15", "CP1252"),
                 ("Код Обмена Информацией, 8 бит", "KOI8-R"),
                 ("国家标准", "GB18030"))
    @test decode(encode(s, enc), enc) == s
end

# Test that attempt to close stream in the middle of incomplete sequence throws
let s = "a string チャネルパートナーの選択"
    # First, correct version
    p = StringEncoder(IOBuffer(), "UTF-16LE")
    write(p, s.data)
    close(p)
    # Test that closed pipe behaves correctly
    @test_throws ArgumentError write(p, 'a')

    b = IOBuffer()
    p = StringEncoder(b, "UTF-16LE")
    @test string(p) == "StringEncoder{UTF-8, UTF-16LE}($(string(b)))"
    write(p, s.data[1:10])
    @test_throws IncompleteSequenceError close(p)
    # Test that closed pipe behaves correctly even after an error
    @test_throws ArgumentError write(p, 'a')

    # This time, call show
    p = StringEncoder(IOBuffer(), "UTF-16LE")
    write(p, s.data[1:10])
    try
        close(p)
    catch err
        @test isa(err, IncompleteSequenceError)
        io = IOBuffer()
        showerror(io, err)
        @test takebuf_string(io) == "Incomplete byte sequence at end of input"
    end

    b = IOBuffer(encode(s, "UTF-16LE")[1:19])
    p = StringDecoder(b, "UTF-16LE")
    @test string(p) == "StringDecoder{UTF-16LE, UTF-8}($(string(b)))"
    @test readstring(p) == s[1:9]
    @test_throws IncompleteSequenceError close(p)
    # Test that closed pipe behaves correctly even after an error
    @test eof(p)
    @test_throws ArgumentError read(p, UInt8)

    # Test stateful encoding, which output some bytes on final reset
    # with strings containing different scripts
    x = encode(s, "ISO-2022-JP")
    @test decode(x, "ISO-2022-JP") == s

    p = StringDecoder(b, "ISO-2022-JP", "UTF-8")
    b = IOBuffer(x)
    # Test that closed pipe behaves correctly
    close(p)
    @test eof(p)
    @test_throws ArgumentError read(p, UInt8)
    close(p)
end

@test_throws InvalidSequenceError encode("qwertyé€", "ASCII")
try
    encode("qwertyé€", "ASCII")
catch err
     io = IOBuffer()
     showerror(io, err)
     @test takebuf_string(io) ==
        "Byte sequence 0xc3a9e282ac is invalid in source encoding or cannot be represented in target encoding"
end

@test_throws InvalidSequenceError decode(b"qwertyé€", "ASCII")
try
    decode(b"qwertyé€", "ASCII")
catch err
     io = IOBuffer()
     showerror(io, err)
     @test takebuf_string(io) ==
         "Byte sequence 0xc3a9e282ac is invalid in source encoding or cannot be represented in target encoding"
end

let x = encode("ÄÆä", "ISO-8859-1")
    @test_throws InvalidSequenceError decode(x, "UTF-8")
    try
        decode(x, "UTF-8")
    catch err
         io = IOBuffer()
         showerror(io, err)
         @test takebuf_string(io) ==
             "Byte sequence 0xc4c6e4 is invalid in source encoding or cannot be represented in target encoding"
    end
end

mktemp() do p, io
    s = "café crème"
    write(io, encode(s, "CP1252"))
    close(io)
    @test readstring(p, enc"CP1252") == s
end

@test_throws InvalidEncodingError p = StringEncoder(IOBuffer(), "nonexistent_encoding")
@test_throws InvalidEncodingError p = StringDecoder(IOBuffer(), "nonexistent_encoding")

try
    p = StringEncoder(IOBuffer(), "nonexistent_encoding", "absurd_encoding")
catch err
    @test isa(err, InvalidEncodingError)
    io = IOBuffer()
    showerror(io, err)
    @test takebuf_string(io) ==
        "Conversion from absurd_encoding to nonexistent_encoding not supported by iconv implementation, check that specified encodings are correct"
end
try
    p = StringDecoder(IOBuffer(), "nonexistent_encoding", "absurd_encoding")
catch err
    @test isa(err, InvalidEncodingError)
    io = IOBuffer()
    showerror(io, err)
    @test takebuf_string(io) ==
        "Conversion from nonexistent_encoding to absurd_encoding not supported by iconv implementation, check that specified encodings are correct"
end

mktemp() do path, io
    s = "a string \0チャネルパ\0ー\0トナーの選択 with embedded and trailing nuls\0\nand a second line"
    close(io)
    open(path, enc"ISO-2022-JP", "w") do io
        @test iswritable(io) && !isreadable(io)
        write(io, s)
    end

    @test readstring(path, enc"ISO-2022-JP") == s
    @test open(io->readstring(io, enc"ISO-2022-JP"), path) == s
    @test open(readstring, path, enc"ISO-2022-JP") == s

    @test readuntil(path, enc"ISO-2022-JP", '\0') == "a string \0"
    @test open(io->readuntil(io, enc"ISO-2022-JP", '\0'), path) == "a string \0"
    @test readuntil(path, enc"ISO-2022-JP", "チャ") == "a string \0チャ"
    @test open(io->readuntil(io, enc"ISO-2022-JP", "チャ"), path) == "a string \0チャ"

    @test readline(path, enc"ISO-2022-JP") == string(split(s, '\n')[1], '\n')
    @test open(readline, path, enc"ISO-2022-JP") == string(split(s, '\n')[1], '\n')
    a = readlines(path, enc"ISO-2022-JP")
    b = open(readlines, path, enc"ISO-2022-JP")

    c = collect(eachline(path, enc"ISO-2022-JP"))
    d = open(io->collect(eachline(io, enc"ISO-2022-JP")), path)

    @test a[1] == b[1] == c[1] == d[1] == string(split(s, '\n')[1], '\n')
    @test a[2] == b[2] == c[2] == d[2] == split(s, '\n')[2]

    # Test alternative syntaxes for open()
    open(path, enc"ISO-2022-JP", "r") do io
        @test isreadable(io) && !iswritable(io)
        @test readstring(io) == s
    end
    open(path, enc"ISO-2022-JP", true, false, false, false, false) do io
        @test isreadable(io) && !iswritable(io)
        @test readstring(io) == s
    end
    @test_throws ArgumentError open(path, enc"ISO-2022-JP", "r+")
    @test_throws ArgumentError open(path, enc"ISO-2022-JP", "w+")
    @test_throws ArgumentError open(path, enc"ISO-2022-JP", "a+")
    @test_throws ArgumentError open(path, enc"ISO-2022-JP", true, true, false, false, false)
    @test_throws ArgumentError open(path, enc"ISO-2022-JP", true, false, false, false, true)
end


## Test encodings support
b = IOBuffer()
show(b, enc"UTF-8")
@test takebuf_string(b) == "UTF-8 string encoding"
@test string(enc"UTF-8") == "UTF-8"

encodings_list = encodings()
@test "ASCII" in encodings_list
@test "UTF-8" in encodings_list

nothing
