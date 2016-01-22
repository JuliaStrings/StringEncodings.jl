# This file is a part of Julia. License is MIT: http://julialang.org/license

module StringEncodings
import Base: close, eof, flush, read, readall, write, show
import Base.Libc: errno, strerror, E2BIG, EINVAL, EILSEQ
export StringEncoder, StringDecoder, encode, decode
export StringEncodingError, OutputBufferError, IConvError
export InvalidEncodingError, InvalidSequenceError, IncompleteSequenceError


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
IConvError(func) = IConvError((func, errno(), strerror(errno())))
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

function iconv_open(tocode, fromcode)
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
    StringEncoder(istream, to, from="UTF-8")

Returns a new write-only I/O stream, which converts any text in the encoding `from`
written to it into text in the encoding `to` written to ostream. Calling `close` on the
stream is necessary to complete the encoding (but does not close `ostream`).
"""
function StringEncoder(ostream::IO, to::ASCIIString, from::ASCIIString="UTF-8")
    cd = iconv_open(to, from)
    inbuf = Vector{UInt8}(BUFSIZE)
    outbuf = Vector{UInt8}(BUFSIZE)
    s = StringEncoder(ostream, cd, inbuf, outbuf,
                      Ref{Ptr{UInt8}}(pointer(inbuf)), Ref{Ptr{UInt8}}(pointer(outbuf)),
                      Ref{Csize_t}(0), Ref{Csize_t}(BUFSIZE))
    finalizer(s, finalize)
    s
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
        write(s.ostream, sub(s.outbuf, 1:(BUFSIZE - s.outbytesleft[])))
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
    StringDecoder(istream, from, to="UTF-8")

Returns a new read-only I/O stream, which converts text in the encoding `from`
read from `istream` into text in the encoding `to`.

Note that some implementations (notably the Windows one) may accept invalid sequences
in the input data without raising an error.
"""
function StringDecoder(istream::IO, from::ASCIIString, to::ASCIIString="UTF-8")
    cd = iconv_open(to, from)
    inbuf = Vector{UInt8}(BUFSIZE)
    outbuf = Vector{UInt8}(BUFSIZE)
    s = StringDecoder(istream, cd, inbuf, outbuf,
                      Ref{Ptr{UInt8}}(pointer(inbuf)), Ref{Ptr{UInt8}}(pointer(outbuf)),
                      Ref{Csize_t}(0), Ref{Csize_t}(BUFSIZE), 0)
    finalizer(s, finalize)
    s
end

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

    s.inbytesleft[] += readbytes!(s.istream, sub(s.inbuf, (s.inbytesleft[]+1):BUFSIZE))
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

function readall(filename::AbstractString, encoding::ASCIIString)
    open(s -> readall(StringDecoder(s, encoding)), filename)
end


## Functions to encode/decode strings

encoding_string(::Type{ASCIIString}) = "ASCII"
encoding_string(::Type{UTF8String})  = "UTF-8"
encoding_string(::Type{UTF16String}) = (ENDIAN_BOM == 0x04030201) ? "UTF-16LE" : "UTF-16BE"
encoding_string(::Type{UTF32String}) = (ENDIAN_BOM == 0x04030201) ? "UTF-32LE" : "UTF-32BE"

"""
    decode(a::Vector{UInt8}, enc::ASCIIString)

Convert an array of bytes `a` representing text in encoding `enc` to a string.

Note that some implementations (notably the Windows one) may accept invalid sequences
in the input data without raising an error.
"""
function decode(a::Vector{UInt8}, enc::ASCIIString)
    b = IOBuffer(a)
    try
        UTF8String(readbytes(StringDecoder(b, enc, "UTF-8")))
    finally
        close(b)
    end
end

"""
    encode(s::AbstractString, enc::ASCIIString)

Convert string `s` to an array of bytes representing text in encoding `enc`.
"""
function encode(s::AbstractString, enc::ASCIIString)
    b = IOBuffer()
    p = StringEncoder(b, enc, encoding_string(typeof(s)))
    write(p, s)
    close(p)
    takebuf_array(b)
end

end # module
