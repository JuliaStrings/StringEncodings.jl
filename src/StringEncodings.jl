# This file is a part of StringEncodings.jl. License is MIT: http://julialang.org/license

module StringEncodings
import Base: close, eof, flush, read, readall, write, show
import Base.Libc: errno, strerror, E2BIG, EINVAL, EILSEQ

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

type StringEncoder{S<:IO} <: IO
    ostream::S
    cd::Ptr{Void}
    inbuf::Vector{UInt8}
    outbuf::Vector{UInt8}
    inbufptr::Ref{Ptr{UInt8}}
    outbufptr::Ref{Ptr{UInt8}}
    inbytesleft::Ref{Csize_t}
    outbytesleft::Ref{Csize_t}
end

type StringDecoder{S<:IO} <: IO
    istream::S
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
    StringEncoder(istream, to, from=enc"UTF-8")

Returns a new write-only I/O stream, which converts any text in the encoding `from`
written to it into text in the encoding `to` written to ostream. Calling `close` on the
stream is necessary to complete the encoding (but does not close `ostream`).

`to` and `from` can be specified either as a string or as an `Encoding` object.
"""
function StringEncoder(ostream::IO, to::Encoding, from::Encoding=enc"UTF-8")
    cd = iconv_open(ASCIIString(to), ASCIIString(from))
    inbuf = Vector{UInt8}(BUFSIZE)
    outbuf = Vector{UInt8}(BUFSIZE)
    s = StringEncoder(ostream, cd, inbuf, outbuf,
                      Ref{Ptr{UInt8}}(pointer(inbuf)), Ref{Ptr{UInt8}}(pointer(outbuf)),
                      Ref{Csize_t}(0), Ref{Csize_t}(BUFSIZE))
    finalizer(s, finalize)
    s
end

StringEncoder(ostream::IO, to::AbstractString, from::Encoding=enc"UTF-8") =
    StringEncoder(ostream, Encoding(to), from)
StringEncoder(ostream::IO, to::AbstractString, from::AbstractString) =
    StringEncoder(ostream, Encoding(to), Encoding(from))

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
        write(s.ostream, sub(s.outbuf, 1:(BUFSIZE - Int(s.outbytesleft[]))))
    end

    s
end

function close(s::StringEncoder)
    flush(s)
    iconv_reset!(s)
    # Make sure C memory/resources are returned
    finalize(s)
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
    StringDecoder(istream, from, to=enc"UTF-8")

Returns a new read-only I/O stream, which converts text in the encoding `from`
read from `istream` into text in the encoding `to`.

`to` and `from` can be specified either as a string or as an `Encoding` object.

Note that some implementations (notably the Windows one) may accept invalid sequences
in the input data without raising an error.
"""
function StringDecoder(istream::IO, from::Encoding, to::Encoding=enc"UTF-8")
    cd = iconv_open(ASCIIString(to), ASCIIString(from))
    inbuf = Vector{UInt8}(BUFSIZE)
    outbuf = Vector{UInt8}(BUFSIZE)
    s = StringDecoder(istream, cd, inbuf, outbuf,
                      Ref{Ptr{UInt8}}(pointer(inbuf)), Ref{Ptr{UInt8}}(pointer(outbuf)),
                      Ref{Csize_t}(0), Ref{Csize_t}(BUFSIZE), 0)
    finalizer(s, finalize)
    s
end

StringDecoder(istream::IO, from::AbstractString, to::Encoding=enc"UTF-8") =
    StringDecoder(istream, Encoding(from), to)
StringDecoder(istream::IO, from::AbstractString, to::AbstractString) =
    StringDecoder(istream, Encoding(from), Encoding(to))

# Fill input buffer and convert it into output buffer
# Returns the number of bytes written to output buffer
function fill_buffer!(s::StringDecoder)
    s.cd == C_NULL && return 0

    s.skip = 0

    # Input buffer and input stream empty
    if s.inbytesleft[] == 0 && eof(s.istream)
        i = iconv_reset!(s)
        return i
    end

    s.inbytesleft[] += readbytes!(s.istream, sub(s.inbuf, Int(s.inbytesleft[]+1):BUFSIZE))
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
    # iconv_reset!() wasn't able to empty input buffer, which cannot happen with correct data
    s.inbytesleft[] == 0 || throw(IncompleteSequenceError())
end

function read(s::StringDecoder, ::Type{UInt8})
    eof(s) ? throw(EOFError()) : s.outbuf[s.skip+=1]
end


## Convenience I/O functions
if isdefined(Base, :readstring)
    @doc """
        readstring(stream or filename, enc::Encoding)

    Read the entire contents of an I/O stream or a file in encoding `enc` as a string.
    """ ->
    Base.readstring(s::IO, enc::Encoding) = readstring(StringDecoder(s, enc))
    Base.readstring(filename::AbstractString, enc::Encoding) = open(io->readstring(io, enc), filename)
else # Compatibility with Julia 0.4
    @doc """
        readall(stream or filename, enc::Encoding)

    Read the entire contents of an I/O stream or a file in encoding `enc` as a string.
    """ ->
    Base.readall(s::IO, enc::Encoding) = readall(StringDecoder(s, enc))
    Base.readall(filename::AbstractString, enc::Encoding) = open(io->readall(io, enc), filename)
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
        T(readbytes(StringDecoder(b, enc, encoding(T))))
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
    close(p)
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
