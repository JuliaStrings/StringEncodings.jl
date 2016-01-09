using Base.Test
using iconv

for s in ("", "a", "café crème",
          "a"^(iconv.BUFSIZE-1) * "€ with an incomplete codepoint between two input buffer fills",
          "a string € チャネルパートナーの選択")
    # Test round-trip to Unicode formats, checking against pure-Julia implementation
    for T in (UTF8String, UTF16String, UTF32String)
        enc = iconv.encoding_string(T)
        a = reinterpret(UInt8, T(s).data)
        @test decode(a, enc) == s
        @test decode(encode(s, enc), enc) == s
    end
end

# Test a few non-Unicode encodings
for (s, enc) in (("noël", "ISO-8859-1"), ("noël €", "ISO-8859-15", "CP1252"),
                   ("Код Обмена Информацией, 8 бит", "KOI8"), ("国家标准", "GB18030"))
    @test decode(encode(s, enc), enc) == s
end

# Test that attempt to close stream in the middle of incomplete sequence throws
# TODO: use more specific errors
let s = "a string € チャネルパートナーの選択"
    p = StringEncoder(IOBuffer(), "UTF-16LE")
    write(p, s.data[1:10])
    @test_throws ErrorException close(p)

    p = StringDecoder(IOBuffer(encode(s, "UTF-16LE")[1:19]), "UTF-16LE")
    @test readall(p) == s[1:9]
    @test_throws ErrorException close(p)

    # Test stateful encoding, which output some bytes on final reset
    # with strings containing different scripts
    x = encode(s, "ISO-2022-JP-3")
    @test decode(x, "ISO-2022-JP-3") == s

    p = StringDecoder(IOBuffer(x), "ISO-2022-JP-3", "UTF-8")
    # Test that closed pipe behaves correctly
    close(p)
    @test eof(p)
    @test_throws EOFError read(p, UInt8)
    close(p)
end

@test_throws ErrorException encode("qwertyé€", "ASCII")
try
    encode("qwertyé€", "ASCII")
catch err
     io = IOBuffer()
     showerror(io, err)
     @test takebuf_string(io) ==
        "iconv error: byte sequence 0xc3a9e282ac is invalid in source encoding or cannot be represented in target encoding"
end

@test_throws ErrorException decode("qwertyé€".data, "ASCII")
try
    decode("qwertyé€".data, "ASCII")
catch err
     io = IOBuffer()
     showerror(io, err)
     @test takebuf_string(io) ==
        "iconv error: byte sequence 0xc3a9e282ac is invalid in source encoding or cannot be represented in target encoding"
end

mktemp() do p, io
    s = "café crème"
    write(io, encode(s, "CP1252"))
    close(io)
    @test readall(p, "CP1252") == s
end

@test_throws ErrorException p = StringEncoder(IOBuffer(), "nonexistent_encoding")
@test_throws ErrorException p = StringDecoder(IOBuffer(), "nonexistent_encoding")
