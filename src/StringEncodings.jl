# This file is a part of StringEncodings.jl. License is MIT: http://julialang.org/license

module StringEncodings
import Base: close, eachline, eof, flush, isreadable, iswritable,
             open, read, readline, readlines, readuntil, show, write
import Base.Libc: errno, strerror, E2BIG, EINVAL, EILSEQ
import Compat: read

export StringEncoder, StringDecoder, encode, decode, encodings
export StringEncodingError, OutputBufferError, IConvError
export InvalidEncodingError, InvalidSequenceError, IncompleteSequenceError

include("encodings.jl")

abstract StringEncodingError

# Specified encodings or the combination are not supported by iconv
type InvalidEncodingError <: StringEncodingError
    args::Tuple{ASCIIString, ASCIIString}
end
InvalidEncodingError(from, to) = InvalidEncodingError((from, to))
message(::Type{InvalidEncodingError}) = "Conversion from <<1>> to <<2>> not supported by iconv implementation, check that specified encodings are correct"

# Encountered invalid byte sequence
type InvalidSequenceError <: StringEncodingError
    args::Tuple{ASCIIString}
end
InvalidSequenceError(seq::Vector{UInt8}) = InvalidSequenceError((bytes2hex(seq),))
message(::Type{InvalidSequenceError}) = "Byte sequence 0x<<1>> is invalid in source encoding or cannot be represented in target encoding"

type IConvError <: StringEncodingError
    args::Tuple{ASCIIString, Int, ASCIIString}
end
IConvError(func::ASCIIString) = IConvError((func, errno(), strerror(errno())))
message(::Type{IConvError}) = "<<1>>: <<2>> (<<3>>)"

# Input ended with incomplete byte sequence
type IncompleteSequenceError <: StringEncodingError ; end
message(::Type{IncompleteSequenceError}) = "Incomplete byte sequence at end of input"

type OutputBufferError <: StringEncodingError ; end
message(::Type{OutputBufferError}) = "Ran out of space in the output buffer"

function show(io::IO, exc::StringEncodingError)
    str = message(typeof(exc))
    for i = 1:length(exc.args)
        str = replace(str, "<<$i>>", exc.args[i])
    end
    print(io, str)
end

show{T<:Union{IncompleteSequenceError,OutputBufferError}}(io::IO, exc::T) =
    print(io, message(T))

depsjl = joinpath(dirname(@__FILE__), "..", "deps", "deps.jl")
isfile(depsjl) ? include(depsjl) : error("libiconv not properly installed. Please run\nPkg.build(\"StringEncodings\")")


## iconv wrappers

function iconv_close(cd::Ptr{Void})
    if cd != C_NULL
        ccall((:iconv_close, libiconv), Cint, (Ptr{Void},), cd) == 0 ||
            throw(IConvError("iconv_close"))
    end
end

function iconv_open(tocode::ASCIIString, fromcode::ASCIIString)
    p = ccall((:iconv_open, libiconv), Ptr{Void}, (Cstring, Cstring), tocode, fromcode)
    if p != Ptr{Void}(-1)
        return p
    elseif errno() == EINVAL
        throw(InvalidEncodingError(fromcode, tocode))
    else
        throw(IConvError("iconv_open"))
    end
end


## StringEncoder and StringDecoder common functions

const BUFSIZE = 100

type StringEncoder{F<:Encoding, T<:Encoding, S<:IO} <: IO
    stream::S
    closestream::Bool
    cd::Ptr{Void}
    inbuf::Vector{UInt8}
    outbuf::Vector{UInt8}
    inbufptr::Ref{Ptr{UInt8}}
    outbufptr::Ref{Ptr{UInt8}}
    inbytesleft::Ref{Csize_t}
    outbytesleft::Ref{Csize_t}
end

type StringDecoder{F<:Encoding, T<:Encoding, S<:IO} <: IO
    stream::S
    closestream::Bool
    cd::Ptr{Void}
    inbuf::Vector{UInt8}
    outbuf::Vector{UInt8}
    inbufptr::Ref{Ptr{UInt8}}
    outbufptr::Ref{Ptr{UInt8}}
    inbytesleft::Ref{Csize_t}
    outbytesleft::Ref{Csize_t}
    skip::Int
end

# This is called during GC, just make sure C memory is returned, don't throw errors
function finalize(s::Union{StringEncoder, StringDecoder})
    if s.cd != C_NULL
        iconv_close(s.cd)
        s.cd = C_NULL
    end
    nothing
end

function iconv!(cd::Ptr{Void}, inbuf::Vector{UInt8}, outbuf::Vector{UInt8},
                inbufptr::Ref{Ptr{UInt8}}, outbufptr::Ref{Ptr{UInt8}},
                inbytesleft::Ref{Csize_t}, outbytesleft::Ref{Csize_t})
    inbufptr[] = pointer(inbuf)
    outbufptr[] = pointer(outbuf)

    inbytesleft_orig = inbytesleft[]
    outbytesleft[] = BUFSIZE

    ret = ccall((:iconv, libiconv), Csize_t,
                (Ptr{Void}, Ptr{Ptr{UInt8}}, Ref{Csize_t}, Ptr{Ptr{UInt8}}, Ref{Csize_t}),
                cd, inbufptr, inbytesleft, outbufptr, outbytesleft)

    if ret == -1 % Csize_t
        err = errno()

        # Should never happen unless a very small buffer is used
        if err == E2BIG && outbytesleft[] == BUFSIZE
            throw(OutputBufferError())
        # Output buffer is full, or sequence is incomplete:
        # copy remaining bytes to the start of the input buffer for next time
        elseif err == E2BIG || err == EINVAL
            copy!(inbuf, 1, inbuf, inbytesleft_orig-inbytesleft[]+1, inbytesleft[])
        elseif err == EILSEQ
            seq = inbuf[(inbytesleft_orig-inbytesleft[]+1):inbytesleft_orig]
            throw(InvalidSequenceError(seq))
        else
            throw(IConvError("iconv"))
        end
    end

    BUFSIZE - outbytesleft[]
end

# Reset iconv to initial state
# Returns the number of bytes written into the output buffer, if any
function iconv_reset!(s::Union{StringEncoder, StringDecoder})
    s.cd == C_NULL && return 0

    s.outbufptr[] = pointer(s.outbuf)
    s.outbytesleft[] = BUFSIZE
    ret = ccall((:iconv, libiconv), Csize_t,
                (Ptr{Void}, Ptr{Ptr{UInt8}}, Ref{Csize_t}, Ptr{Ptr{UInt8}}, Ref{Csize_t}),
                s.cd, C_NULL, C_NULL, s.outbufptr, s.outbytesleft)

    if ret == -1 % Csize_t
        err = errno()
        if err == EINVAL
            throw(IncompleteSequenceError())
        elseif err == E2BIG
            throw(OutputBufferError())
        else
            throw(IConvError("iconv"))
        end
    end

    BUFSIZE - s.outbytesleft[]
end


## StringEncoder

"""
    StringEncoder(stream, to, from=enc"UTF-8")

Returns a new write-only I/O stream, which converts any text in the encoding `from`
written to it into text in the encoding `to` written to `stream`. Calling `close` on the
stream is necessary to complete the encoding (but does not close `stream`).

`to` and `from` can be specified either as a string or as an `Encoding` object.
"""
function StringEncoder(stream::IO, to::Encoding, from::Encoding=enc"UTF-8")
    cd = iconv_open(ASCIIString(to), ASCIIString(from))
    inbuf = Vector{UInt8}(BUFSIZE)
    outbuf = Vector{UInt8}(BUFSIZE)
    s = StringEncoder{typeof(from), typeof(to), typeof(stream)}(stream, false,
                      cd, inbuf, outbuf,
                      Ref{Ptr{UInt8}}(pointer(inbuf)), Ref{Ptr{UInt8}}(pointer(outbuf)),
                      Ref{Csize_t}(0), Ref{Csize_t}(BUFSIZE))
    finalizer(s, finalize)
    s
end

StringEncoder(stream::IO, to::AbstractString, from::Encoding=enc"UTF-8") =
    StringEncoder(stream, Encoding(to), from)
StringEncoder(stream::IO, to::AbstractString, from::AbstractString) =
    StringEncoder(stream, Encoding(to), Encoding(from))

function show{F, T, S}(io::IO, s::StringEncoder{F, T, S})
    from = F()
    to = T()
    print(io, "StringEncoder{$from, $to}($(s.stream))")
end

# Flush input buffer and convert it into output buffer
# Returns the number of bytes written to output buffer
function flush(s::StringEncoder)
    s.cd == C_NULL && return s

    # We need to retry several times in case output buffer is too small to convert
    # all of the input. Even so, some incomplete sequences may remain in the input
    # until more data is written, which will only trigger an error on close().
    s.outbytesleft[] = 0
    while s.outbytesleft[] < BUFSIZE
        iconv!(s.cd, s.inbuf, s.outbuf, s.inbufptr, s.outbufptr, s.inbytesleft, s.outbytesleft)
        write(s.stream, sub(s.outbuf, 1:(BUFSIZE - Int(s.outbytesleft[]))))
    end

    s
end

function close(s::StringEncoder)
    flush(s)
    iconv_reset!(s)
    # Make sure C memory/resources are returned
    finalize(s)
    if s.closestream
        close(s.stream)
    end
    # flush() wasn't able to empty input buffer, which cannot happen with correct data
    s.inbytesleft[] == 0 || throw(IncompleteSequenceError())
end

function write(s::StringEncoder, x::UInt8)
    s.inbytesleft[] >= length(s.inbuf) && flush(s)
    s.inbuf[s.inbytesleft[]+=1] = x
    1
end


## StringDecoder

"""
    StringDecoder(stream, from, to=enc"UTF-8")

Returns a new read-only I/O stream, which converts text in the encoding `from`
read from `stream` into text in the encoding `to`.  Calling `close` on the
stream does not close `stream`.

`to` and `from` can be specified either as a string or as an `Encoding` object.

Note that some implementations (notably the Windows one) may accept invalid sequences
in the input data without raising an error.
"""
function StringDecoder(stream::IO, from::Encoding, to::Encoding=enc"UTF-8")
    cd = iconv_open(ASCIIString(to), ASCIIString(from))
    inbuf = Vector{UInt8}(BUFSIZE)
    outbuf = Vector{UInt8}(BUFSIZE)
    s = StringDecoder{typeof(from), typeof(to), typeof(stream)}(stream, false,
                      cd, inbuf, outbuf,
                      Ref{Ptr{UInt8}}(pointer(inbuf)), Ref{Ptr{UInt8}}(pointer(outbuf)),
                      Ref{Csize_t}(0), Ref{Csize_t}(BUFSIZE), 0)
    finalizer(s, finalize)
    s
end

StringDecoder(stream::IO, from::AbstractString, to::Encoding=enc"UTF-8") =
    StringDecoder(stream, Encoding(from), to)
StringDecoder(stream::IO, from::AbstractString, to::AbstractString) =
    StringDecoder(stream, Encoding(from), Encoding(to))

function show{F, T, S}(io::IO, s::StringDecoder{F, T, S})
    from = F()
    to = T()
    print(io, "StringDecoder{$from, $to}($(s.stream))")
end

# Fill input buffer and convert it into output buffer
# Returns the number of bytes written to output buffer
function fill_buffer!(s::StringDecoder)
    s.cd == C_NULL && return 0

    s.skip = 0

    # Input buffer and input stream empty
    if s.inbytesleft[] == 0 && eof(s.stream)
        i = iconv_reset!(s)
        return i
    end

    s.inbytesleft[] += readbytes!(s.stream, sub(s.inbuf, Int(s.inbytesleft[]+1):BUFSIZE))
    iconv!(s.cd, s.inbuf, s.outbuf, s.inbufptr, s.outbufptr, s.inbytesleft, s.outbytesleft)
end

# In order to know whether more data is available, we need to:
# 1) check whether the output buffer contains data
# 2) if not, actually try to fill it (this is the only way to find out whether input
#    data contains only state control sequences which may be converted to nothing)
# 3) if not, reset iconv to initial state, which may generate data
function eof(s::StringDecoder)
    length(s.outbuf) - s.outbytesleft[] == s.skip &&
        fill_buffer!(s) == 0 &&
        iconv_reset!(s) == 0
end

function close(s::StringDecoder)
    iconv_reset!(s)
    # Make sure C memory/resources are returned
    finalize(s)
    if s.closestream
        close(s.stream)
    end
    # iconv_reset!() wasn't able to empty input buffer, which cannot happen with correct data
    s.inbytesleft[] == 0 || throw(IncompleteSequenceError())
end

function read(s::StringDecoder, ::Type{UInt8})
    eof(s) ? throw(EOFError()) : s.outbuf[s.skip+=1]
end

isreadable(s::StringDecoder) = isreadable(s.stream)
iswritable(s::StringDecoder) = false

isreadable(s::StringEncoder) = false
iswritable(s::StringEncoder) = iswritable(s.stream)


## Convenience I/O functions
function wrap_stream(s::IO, enc::Encoding)
    if iswritable(s) && isreadable(s) # Should never happen
        throw(ArgumentError("cannot open encoded text files in read and write/append modes at the same time"))
    end
    s = iswritable(s) ? StringEncoder(s, enc) : StringDecoder(s, enc)
    s.closestream = true
    s
end

"""
    open(filename::AbstractString, enc::Encoding[, args...])

Open a text file in encoding `enc`, converting its contents to UTF-8 on the fly
using `StringDecoder` (when reading) or `StringEncoder` (when writing).
`args` is passed to `open`, so this function can be used as a replacement for all `open`
variants for working with files.

Note that calling `close` on the returned I/O stream will also close the associated file handle;
this operation is necessary to complete the encoding in write mode. Opening a file for both
reading and writing/appending is not supported.

The returned I/O stream can be passed to functions working on strings without
specifying the encoding again.
"""
open(fname::AbstractString, enc::Encoding, args...) = wrap_stream(open(fname, args...), enc)

function open(fname::AbstractString, enc::Encoding,
              rd::Bool, wr::Bool, cr::Bool, tr::Bool, ff::Bool)
    if rd && (wr || ff)
        throw(ArgumentError("cannot open encoded text files in read and write/append modes at the same time"))
    end
    wrap_stream(open(fname, rd, wr, cr, tr, ff), enc)
end

function open(fname::AbstractString, enc::Encoding, mode::AbstractString)
    if mode in ("r+", "w+", "a+")
        throw(ArgumentError("cannot open encoded text files in read and write/append modes at the same time"))
    end
    wrap_stream(open(fname, mode), enc)
end

if isdefined(Base, :readstring)
    @doc """
        readstring(stream::IO, enc::Encoding)
        readstring(filename::AbstractString, enc::Encoding)

    Methods to read text in character encoding `enc`.
    """ ->
    Base.readstring(s::IO, enc::Encoding) = readstring(StringDecoder(s, enc))
    Base.readstring(filename::AbstractString, enc::Encoding) = open(io->readstring(io, enc), filename)
else # Compatibility with Julia 0.4
    @doc """
        readall(stream::IO, enc::Encoding)
        readall(filename::AbstractString, enc::Encoding)

    Methods to read text in character encoding `enc`.
    """ ->
    Base.readall(s::IO, enc::Encoding) = readall(StringDecoder(s, enc))
    Base.readall(filename::AbstractString, enc::Encoding) = open(io->readall(io, enc), filename)
end

"""
    readline(stream::IO, enc::Encoding)
    readline(filename::AbstractString, enc::Encoding)

Methods to read text in character encoding `enc`.
"""
readline(s::IO, enc::Encoding) = readline(StringDecoder(s, enc))
readline(filename::AbstractString, enc::Encoding) = open(io->readline(io, enc), filename)

"""
    readlines(stream::IO, enc::Encoding)
    readlines(filename::AbstractString, enc::Encoding)

Methods to read text in character encoding `enc`.
"""
readlines(s::IO, enc::Encoding) = readlines(StringDecoder(s, enc))
readlines(filename::AbstractString, enc::Encoding) = open(io->readlines(io, enc), filename)

"""
    readuntil(stream::IO, enc::Encoding, delim)
    readuntil(filename::AbstractString, enc::Encoding, delim)

Methods to read text in character encoding `enc`.
"""
readuntil(s::IO, enc::Encoding, delim) = readuntil(StringDecoder(s, enc), delim)
readuntil(filename::AbstractString, enc::Encoding, delim) = open(io->readuntil(io, enc, delim), filename)

"""
    eachline(stream::IO, enc::Encoding)
    eachline(filename::AbstractString, enc::Encoding)

Methods to read text in character encoding `enc`. Decoding is performed on the fly.
"""
eachline(s::IO, enc::Encoding) = eachline(StringDecoder(s, enc))
function eachline(filename::AbstractString, enc::Encoding)
    s = open(filename, enc)
    EachLine(s, ()->close(s))
end


## Functions to encode/decode strings

"""
    decode([T,] a::Vector{UInt8}, enc)

Convert an array of bytes `a` representing text in encoding `enc` to a string of type `T`.
By default, a `UTF8String` is returned.

`enc` can be specified either as a string or as an `Encoding` object.

Note that some implementations (notably the Windows one) may accept invalid sequences
in the input data without raising an error.
"""
function decode{T<:AbstractString}(::Type{T}, a::Vector{UInt8}, enc::Encoding)
    b = IOBuffer(a)
    try
        T(read(StringDecoder(b, enc, encoding(T))))
    finally
        close(b)
    end
end

decode{T<:AbstractString}(::Type{T}, a::Vector{UInt8}, enc::AbstractString) = decode(T, a, Encoding(enc))

decode(a::Vector{UInt8}, enc::AbstractString) = decode(UTF8String, a, Encoding(enc))
decode(a::Vector{UInt8}, enc::Union{AbstractString, Encoding}) = decode(UTF8String, a, enc)

"""
    encode(s::AbstractString, enc)

Convert string `s` to an array of bytes representing text in encoding `enc`.
`enc` can be specified either as a string or as an `Encoding` object.
"""
function encode(s::AbstractString, enc::Encoding)
    b = IOBuffer()
    p = StringEncoder(b, enc, encoding(typeof(s)))
    write(p, s)
    flush(p)
    takebuf_array(b)
end

encode(s::AbstractString, enc::AbstractString) = encode(s, Encoding(enc))

function test_encoding(enc::ASCIIString)
    # We assume that an encoding is supported if it's possible to convert from it to UTF-8:
    cd = ccall((:iconv_open, libiconv), Ptr{Void}, (Cstring, Cstring), enc, "UTF-8")
    if cd == Ptr{Void}(-1)
        return false
    else
        iconv_close(cd)
        return true
    end
end

"""
    encodings()

List all encodings supported by `encode`, `decode`, `StringEncoder` and `StringDecoder`
(i.e. by the current iconv implementation).

Note that encodings typically appear several times under different names.
In addition to the encodings returned by this function, the empty string (i.e. `""`)
is equivalent to the encoding of the current locale.

Some implementations may support even more encodings: this can be checked by attempting
a conversion. In theory, it is not guaranteed that all conversions between all pairs of encodings
are possible; but this is the case with all reasonable implementations.
"""
function encodings()
    filter(test_encoding, encodings_list)
end

end # module
