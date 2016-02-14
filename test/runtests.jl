using Base.Test
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
# TODO: use more specific errors
let s = "a string チャネルパートナーの選択"
    p = StringEncoder(IOBuffer(), "UTF-16LE")
    write(p, s.data[1:10])
    @test_throws IncompleteSequenceError close(p)

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

    p = StringDecoder(IOBuffer(encode(s, "UTF-16LE")[1:19]), "UTF-16LE")
    @test readall(p) == s[1:9]
    @test_throws IncompleteSequenceError close(p)

    # Test stateful encoding, which output some bytes on final reset
    # with strings containing different scripts
    x = encode(s, "ISO-2022-JP")
    @test decode(x, "ISO-2022-JP") == s

    p = StringDecoder(IOBuffer(x), "ISO-2022-JP", "UTF-8")
    # Test that closed pipe behaves correctly
    close(p)
    @test eof(p)
    @test_throws EOFError read(p, UInt8)
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

# win_iconv currently does not throw an error on bytes >= 0x80 in ASCII sources
# https://github.com/win-iconv/win-iconv/pull/26
if OS_NAME != :Windows
    @test_throws InvalidSequenceError decode(b"qwertyé€", "ASCII")
    try
        decode(b"qwertyé€", "ASCII")
    catch err
         io = IOBuffer()
         showerror(io, err)
         @test takebuf_string(io) ==
             "Byte sequence 0xc3a9e282ac is invalid in source encoding or cannot be represented in target encoding"
    end
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
    @test readall(p, enc"CP1252") == s
end

@test_throws InvalidEncodingError p = StringEncoder(IOBuffer(), "nonexistent_encoding")
@test_throws InvalidEncodingError p = StringDecoder(IOBuffer(), "nonexistent_encoding")

try
    p = StringEncoder(IOBuffer(), "nonexistent_encoding")
catch err
    @test isa(err, InvalidEncodingError)
    io = IOBuffer()
    showerror(io, err)
    @test takebuf_string(io) ==
        "Conversion from UTF-8 to nonexistent_encoding not supported by iconv implementation, check that specified encodings are correct"
end
try
    p = StringDecoder(IOBuffer(), "nonexistent_encoding")
catch err
    @test isa(err, InvalidEncodingError)
    io = IOBuffer()
    showerror(io, err)
    @test takebuf_string(io) ==
        "Conversion from nonexistent_encoding to UTF-8 not supported by iconv implementation, check that specified encodings are correct"
end

if !isdefined(Base, :readstring)
    readstring = readall
end

mktemp() do path, io
    s = "a string \0チャネルパ\0ー\0トナーの選択 with embedded and trailing nuls\0"
    write(io, encode(s, "ISO-2022-JP"))
    close(io)

    @test readstring(path, enc"ISO-2022-JP") == s
    @test open(io->readstring(io, enc"ISO-2022-JP"), path) == s
end


## Test encodings support

encodings_list = encodings()
@test "ASCII" in encodings_list
@test "UTF-8" in encodings_list

@test native_endian(enc"ASCII") == native_endian(enc"UTF-8") == true
@test native_endian(enc"UTF-16LE") == native_endian(enc"UTF16LE") == (ENDIAN_BOM == 0x04030201)
@test native_endian(enc"UTF-16BE") == native_endian(enc"UTF16BE") == (ENDIAN_BOM != 0x04030201)
@test native_endian(enc"UTF-32LE") == native_endian(enc"UTF32LE") == (ENDIAN_BOM == 0x04030201)
@test native_endian(enc"UTF-32BE") == native_endian(enc"UTF32BE") == (ENDIAN_BOM != 0x04030201)

@test codeunit(enc"ASCII") == UInt8
@test codeunit(enc"UTF-8") == UInt8
@test codeunit(enc"UTF-16") == codeunit(enc"UTF-16LE") == codeunit(enc"UTF-16BE") == UInt16
@test codeunit(enc"UTF-32") == codeunit(enc"UTF-32LE") == codeunit(enc"UTF-32BE") == UInt32

nothing

