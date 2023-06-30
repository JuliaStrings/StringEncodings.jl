using Test
using StringEncodings

# Test round-trip to Unicode formats
for s in ("", "\0", "a", "café crème",
          "a"^(StringEncodings.BUFSIZE-1) * "€ with an incomplete codepoint between two input buffer fills",
          "a string € チャネルパートナーの選択",
          "a string \0€ チャネルパ\0ー\0トナーの選択 with embedded and trailing nuls\0"),
    enc in (enc"UTF-8", enc"UTF-16", enc"UTF-16LE", enc"UTF-16BE", enc"UTF-32")
    a = encode(s, enc)
    @test decode(a, enc) == s
    @test decode(encode(s, enc), enc) == s
end

# Test a few non-Unicode encodings
for (s, enc) in (("noël", "ISO-8859-1"),
                 ("noël €", "ISO-8859-15", "CP1252"),
                 ("Код Обмена Информацией, 8 бит", "KOI8-R"),
                 ("国家标准", "GB18030"))
    @test decode(encode(s, enc), enc) == s
end

# Test that attempt to close stream in the middle of incomplete sequence throws
let s = "a string チャネルパートナーの選択", a = unsafe_wrap(Vector{UInt8}, s)
    # First, correct version
    p = StringEncoder(IOBuffer(), "UTF-16LE")
    write(p, a)
    close(p)
    # Test that closed pipe behaves correctly
    @test_throws ArgumentError write(p, 'a')

    b = IOBuffer()
    p = StringEncoder(b, "UTF-16LE")
    @test string(p) == "StringEncoder{UTF-8, UTF-16LE}($(string(b)))"
    write(p, a[1:10])
    @test_throws IncompleteSequenceError close(p)
    # Test that closed pipe behaves correctly even after an error
    @test_throws ArgumentError write(p, 'a')

    # This time, call show
    p = StringEncoder(IOBuffer(), "UTF-16LE")
    write(p, a[1:10])
    try
        close(p)
    catch err
        @test isa(err, IncompleteSequenceError)
        io = IOBuffer()
        showerror(io, err)
        @test String(take!(io)) == "Incomplete byte sequence at end of input"
    end

    b = IOBuffer(encode(s, "UTF-16LE")[1:19])
    p = StringDecoder(b, "UTF-16LE")
    @test string(p) == "StringDecoder{UTF-16LE, UTF-8}($(string(b)))"
    @test read(p, String) == s[1:9]
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
     @test String(take!(io)) ==
        "Byte sequence 0xc3a9e282ac is invalid in source encoding or cannot be represented in target encoding"
end

@test_throws InvalidSequenceError decode(Vector{UInt8}("qwertyé€"), "ASCII")
try
    decode(Vector{UInt8}("qwertyé€"), "ASCII")
catch err
     io = IOBuffer()
     showerror(io, err)
     @test String(take!(io)) ==
         "Byte sequence 0xc3a9e282ac is invalid in source encoding or cannot be represented in target encoding"
end

let x = encode("ÄÆä", "ISO-8859-1")
    @test_throws InvalidSequenceError decode(x, "UTF-8")
    try
        decode(x, "UTF-8")
    catch err
         io = IOBuffer()
         showerror(io, err)
         @test String(take!(io)) ==
             "Byte sequence 0xc4c6e4 is invalid in source encoding or cannot be represented in target encoding"
    end
end

mktemp() do p, io
    s = "café crème"
    write(io, encode(s, "CP1252"))
    close(io)
    @test read(p, String, enc"CP1252") == s
end

@test_throws InvalidEncodingError p = StringEncoder(IOBuffer(), "nonexistent_encoding")
@test_throws InvalidEncodingError p = StringDecoder(IOBuffer(), "nonexistent_encoding")

try
    p = StringEncoder(IOBuffer(), "nonexistent_encoding", "absurd_encoding")
catch err
    @test isa(err, InvalidEncodingError)
    io = IOBuffer()
    showerror(io, err)
    @test String(take!(io)) ==
        "Conversion from absurd_encoding to nonexistent_encoding not supported by iconv implementation, check that specified encodings are correct"
end
try
    p = StringDecoder(IOBuffer(), "nonexistent_encoding", "absurd_encoding")
catch err
    @test isa(err, InvalidEncodingError)
    io = IOBuffer()
    showerror(io, err)
    @test String(take!(io)) ==
        "Conversion from nonexistent_encoding to absurd_encoding not supported by iconv implementation, check that specified encodings are correct"
end

mktemp() do path, io
    s = "a string \0チャネルパ\0ー\0トナーの選択 with embedded and trailing nuls\0\nand a second line"
    close(io)
    open(path, enc"ISO-2022-JP", "w") do io
        @test iswritable(io) && !isreadable(io)
        write(io, s)
    end

    nc = ncodeunits(first(s, 90))

    @test String(read(path, enc"ISO-2022-JP")) == s
    @test String(open(io->read(io, enc"ISO-2022-JP"), path)) == s
    @test String(open(io->read(io), path, enc"ISO-2022-JP")) == s

    @test String(read(path, 1000, enc"ISO-2022-JP")) == s
    @test String(open(io->read(io, 1000, enc"ISO-2022-JP"), path)) == s
    @test String(open(io->read(io, 1000), path, enc"ISO-2022-JP")) == s

    @test String(read(path, nc, enc"ISO-2022-JP")) == first(s, nc)
    @test String(open(io->read(io, nc, enc"ISO-2022-JP"), path)) == first(s, nc)
    @test String(open(io->read(io, nc), path, enc"ISO-2022-JP")) == first(s, nc)

    @test read(path, String, enc"ISO-2022-JP") == s
    @test open(io->read(io, String, enc"ISO-2022-JP"), path) == s
    @test open(io->read(io, String), path, enc"ISO-2022-JP") == s

    b = zeros(UInt8, nc)
    @test open(io->read!(io, b), path, enc"ISO-2022-JP") === b
    @test String(b) == first(s, 90)

    b = zeros(UInt8, nc)
    @test open(io->readbytes!(io, b), path, enc"ISO-2022-JP") == ncodeunits(s)
    @test String(b) == s

    b = zeros(UInt8, 1000)
    @test open(io->readbytes!(io, b), path, enc"ISO-2022-JP") == ncodeunits(s)
    @test length(b) == 1000
    @test String(b[1:ncodeunits(s)]) == s

    b = UInt8[]
    @test open(io->readbytes!(io, b), path, enc"ISO-2022-JP") == 0
    @test length(b) == 0

    b = zeros(UInt8, nc)
    @test open(io->readbytes!(io, b, nc), path, enc"ISO-2022-JP") == nc
    @test String(b) == first(s, 90)

    b = zeros(UInt8, 1000)
    @test open(io->readbytes!(io, b, nc), path, enc"ISO-2022-JP") == nc
    @test length(b) == 1000
    @test String(b[1:nc]) == first(s, 90)

    b = UInt8[]
    @test open(io->readbytes!(io, b, nc), path, enc"ISO-2022-JP") == nc
    @test String(b) == first(s, 90)

    b = UInt8[]
    open(io->while !eof(io); push!(b, read(io, UInt8)) end, path, enc"ISO-2022-JP")
    @test String(b) == s

    @test readuntil(path, enc"ISO-2022-JP", '\0') == "a string "
    @test open(io->readuntil(io, enc"ISO-2022-JP", '\0'), path) == "a string "
    @test open(io->readuntil(io, enc"ISO-2022-JP", '\0', keep=true), path) == "a string \0"
    @test readuntil(path, enc"ISO-2022-JP", "チャ") == "a string \0"
    @test open(io->readuntil(io, enc"ISO-2022-JP", "チャ"), path) == "a string \0"
    @test open(io->readuntil(io, enc"ISO-2022-JP", "チャ", keep=true), path) == "a string \0チャ"

    @test readline(path, enc"ISO-2022-JP") == split(s, '\n')[1]
    @test readline(path, enc"ISO-2022-JP", keep=true) == split(s, '\n', )[1] * '\n'
    @test open(readline, path, enc"ISO-2022-JP") == split(s, '\n')[1]

    a = readlines(path, enc"ISO-2022-JP")
    b = open(readlines, path, enc"ISO-2022-JP")
    c = collect(eachline(path, enc"ISO-2022-JP"))
    d = open(io->collect(eachline(io, enc"ISO-2022-JP")), path)
    @test a[1] == b[1] == c[1] == d[1] == split(s, '\n')[1]
    @test a[2] == b[2] == c[2] == d[2] == split(s, '\n')[2]

    a = readlines(path, enc"ISO-2022-JP", keep=true)
    b = open(io->readlines(io, keep=true), path, enc"ISO-2022-JP")
    c = collect(eachline(path, enc"ISO-2022-JP", keep=true))
    d = open(io->collect(eachline(io, enc"ISO-2022-JP", keep=true)), path)
    @test a[1] == b[1] == c[1] == d[1] == split(s, '\n')[1] * '\n'
    @test a[2] == b[2] == c[2] == d[2] == split(s, '\n')[2]

    # Test alternative syntaxes for open()
    open(path, enc"ISO-2022-JP", "r") do io
        @test isreadable(io) && !iswritable(io)
        @test read(io, String) == s
    end
    open(path, enc"ISO-2022-JP", true, false, false, false, false) do io
        @test isreadable(io) && !iswritable(io)
        @test read(io, String) == s
    end
    @test_throws ArgumentError open(path, enc"ISO-2022-JP", "r+")
    @test_throws ArgumentError open(path, enc"ISO-2022-JP", "w+")
    @test_throws ArgumentError open(path, enc"ISO-2022-JP", "a+")
    @test_throws ArgumentError open(path, enc"ISO-2022-JP", true, true, false, false, false)
    @test_throws ArgumentError open(path, enc"ISO-2022-JP", true, false, false, false, true)
end

@testset "Bytes written only when closing with Shift JIS (issue #49)" begin
    for enc in ("SHIFT_JIS", "SHIFT_JISX0213")
        @test encode("ク", enc) == [0x83, 0x4e]

        b = IOBuffer()
        s = StringEncoder(b, enc)
        write(s, "ク")
        close(s)
        @test take!(b) == [0x83, 0x4e]
    end
end

@testset "readavailable and bytesavailable" begin
    s = "a string チャネルパートナーの選択"^10
    b = IOBuffer(encode(s, "UTF-16LE"))
    p = StringDecoder(b, "UTF-16LE")
    @test read(p, String) == s

    b = IOBuffer(encode(s, "UTF-16LE"))
    p = StringDecoder(b, "UTF-16LE")
    @test bytesavailable(p) == 0
    @test read(p, UInt8) === 0x61
    @test bytesavailable(p) == 197
    @test String(readavailable(p)) == s[2:196]
    @test bytesavailable(p) == 0
    @test String(readavailable(p)) == s[199:394]
    @test bytesavailable(p) == 0
    @test String(readavailable(p)) == s[397:end]
    @test isempty(readavailable(p))
    @test bytesavailable(p) == 0
    @test eof(p)
    close(p)
    @test bytesavailable(p) == 0
    @test_throws ArgumentError readavailable(p)
end

# make sure encode/decode support various string/array types
@testset "Array/String types" begin
    s = "Bendaña"
    enc = "Windows-1252"
    se = "Benda\xf1a"
    @test encode(Test.GenericString(s), enc) == codeunits(se)
    @test encode(SubString(s, 1:6), enc) == encode(s[1:6], enc) == codeunits(se)[1:6]
    @test s == decode(codeunits(se), enc) == decode(collect(codeunits(se)), enc)
    @test s[1:6] == decode(@view(collect(codeunits(se))[1:6]), enc)
end

## Test encodings support
b = IOBuffer()
show(b, enc"UTF-8")
@test String(take!(b)) == "UTF-8 string encoding"
@test string(enc"UTF-8") == "UTF-8"

encodings_list = encodings()
@test "ASCII" in encodings_list
@test "UTF-8" in encodings_list

nothing
