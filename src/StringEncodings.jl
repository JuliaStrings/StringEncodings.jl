# This file is a part of StringEncodings.jl. License is MIT: http://julialang.org/license

module StringEncodings

using Libiconv_jll

using Base.Libc: errno, strerror, E2BIG, EINVAL, EILSEQ

import Base: bytesavailable, close, eachline, eof, flush, isreadable, iswritable,
             open, read, readavailable, readbytes!, readline, readlines,
             readuntil, show, write

export StringEncoder, StringDecoder, encode, decode, encodings
export StringEncodingError, OutputBufferError, IConvError
export InvalidEncodingError, InvalidSequenceError, IncompleteSequenceError

include("encodings.jl")
using StringEncodings.Encodings
export encoding, encodings_list, Encoding, @enc_str

abstract type StringEncodingError end

# contiguous 1d byte arrays compatible with C `unsigned char *` API
const ByteVector= Union{Vector{UInt8},
                        Base.FastContiguousSubArray{UInt8,1,<:Array{UInt8,1}},
                        Base.CodeUnits{UInt8, String}, Base.CodeUnits{UInt8, SubString{String}}}
const ByteString = Union{String,SubString{String}}

# Specified encodings or the combination are not supported by iconv
struct InvalidEncodingError <: StringEncodingError
    args::Tuple{String, String}
end
InvalidEncodingError(from, to) = InvalidEncodingError((from, to))
message(::Type{InvalidEncodingError}) = "Conversion from <<1>> to <<2>> not supported by iconv implementation, check that specified encodings are correct"

# Encountered invalid byte sequence
struct InvalidSequenceError <: StringEncodingError
    args::Tuple{String}
end
InvalidSequenceError(seq::AbstractVector{UInt8}) = InvalidSequenceError((bytes2hex(seq),))
message(::Type{InvalidSequenceError}) = "Byte sequence 0x<<1>> is invalid in source encoding or cannot be represented in target encoding"

struct IConvError <: StringEncodingError
    args::Tuple{String, Int, String}
end
IConvError(func::String) = IConvError((func, errno(), strerror(errno())))
message(::Type{IConvError}) = "<<1>>: <<2>> (<<3>>)"

# Input ended with incomplete byte sequence
struct IncompleteSequenceError <: StringEncodingError ; end
message(::Type{IncompleteSequenceError}) = "Incomplete byte sequence at end of input"

struct OutputBufferError <: StringEncodingError ; end
message(::Type{OutputBufferError}) = "Ran out of space in the output buffer"

function show(io::IO, exc::StringEncodingError)
    str = message(typeof(exc))
    for i = 1:length(exc.args)
        str = replace(str, "<<$i>>" => exc.args[i])
    end
    print(io, str)
end

show(io::IO, exc::T) where {T<:Union{IncompleteSequenceError,OutputBufferError}} =
    print(io, message(T))


## iconv wrappers

function iconv_close(cd::Ptr{Nothing})
    if cd != C_NULL
        ccall((:libiconv_close, libiconv), Cint, (Ptr{Nothing},), cd) == 0 ||
            throw(IConvError("iconv_close"))
    end
end

function iconv_open(tocode::String, fromcode::String)
    p = ccall((:libiconv_open, libiconv), Ptr{Nothing}, (Cstring, Cstring), tocode, fromcode)
    if p != Ptr{Nothing}(-1)
        return p
    elseif errno() == EINVAL
        throw(InvalidEncodingError(fromcode, tocode))
    else
        throw(IConvError("iconv_open"))
    end
end


## StringEncoder and StringDecoder common functions

const BUFSIZE = 200

mutable struct StringEncoder{F<:Encoding, T<:Encoding, S<:IO} <: IO
    stream::S
    closestream::Bool
    cd::Ptr{Nothing}
    inbuf::Vector{UInt8}
    outbuf::Vector{UInt8}
    inbufptr::Ref{Ptr{UInt8}}
    outbufptr::Ref{Ptr{UInt8}}
    inbytesleft::Ref{Csize_t}
    outbytesleft::Ref{Csize_t}
end

mutable struct StringDecoder{F<:Encoding, T<:Encoding, S<:IO} <: IO
    stream::S
    closestream::Bool
    cd::Ptr{Nothing}
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
        # To ensure that eof() returns true without an additional check
        if isa(s, StringDecoder)
            s.outbytesleft[] = BUFSIZE
            s.skip = 0
        end
    end
    nothing
end

function iconv!(cd::Ptr{Nothing}, inbuf::ByteVector, outbuf::ByteVector,
                inbufptr::Ref{Ptr{UInt8}}, outbufptr::Ref{Ptr{UInt8}},
                inbytesleft::Ref{Csize_t}, outbytesleft::Ref{Csize_t})
    inbufptr[] = pointer(inbuf)
    outbufptr[] = pointer(outbuf)

    inbytesleft_orig = inbytesleft[]
    outbytesleft[] = BUFSIZE

    ret = ccall((:libiconv, libiconv), Csize_t,
                (Ptr{Nothing}, Ptr{Ptr{UInt8}}, Ref{Csize_t}, Ptr{Ptr{UInt8}}, Ref{Csize_t}),
                cd, inbufptr, inbytesleft, outbufptr, outbytesleft)

    if ret == -1 % Csize_t
        err = errno()

        # Should never happen unless a very small buffer is used
        if err == E2BIG && outbytesleft[] == BUFSIZE
            throw(OutputBufferError())
        # Output buffer is full, or sequence is incomplete:
        # copy remaining bytes to the start of the input buffer for next time
        elseif err == E2BIG || err == EINVAL
            copyto!(inbuf, 1, inbuf, inbytesleft_orig-inbytesleft[]+1, inbytesleft[])
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
    ret = ccall((:libiconv, libiconv), Csize_t,
                (Ptr{Nothing}, Ptr{Ptr{UInt8}}, Ref{Csize_t}, Ptr{Ptr{UInt8}}, Ref{Csize_t}),
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
returned object is necessary to complete the encoding (but it does not close `stream`).

`to` and `from` can be specified either as a string or as an `Encoding` object.
"""
function StringEncoder(stream::IO, to::Encoding, from::Encoding=enc"UTF-8")
    cd = iconv_open(String(to), String(from))
    inbuf = Vector{UInt8}(undef, BUFSIZE)
    outbuf = Vector{UInt8}(undef, BUFSIZE)
    s = StringEncoder{typeof(from), typeof(to), typeof(stream)}(stream, false,
                      cd, inbuf, outbuf,
                      Ref{Ptr{UInt8}}(pointer(inbuf)), Ref{Ptr{UInt8}}(pointer(outbuf)),
                      Ref{Csize_t}(0), Ref{Csize_t}(BUFSIZE))
    finalizer(finalize, s)
    s
end

StringEncoder(stream::IO, to::AbstractString, from::Encoding=enc"UTF-8") =
    StringEncoder(stream, Encoding(to), from)
StringEncoder(stream::IO, to::AbstractString, from::AbstractString) =
    StringEncoder(stream, Encoding(to), Encoding(from))

function show(io::IO, s::StringEncoder{F, T}) where {F, T}
    from = F()
    to = T()
    print(io, "StringEncoder{$from, $to}($(s.stream))")
end

# Flush input buffer and convert it into output buffer
function flush(s::StringEncoder)
    s.cd == C_NULL && return s

    # We need to retry several times in case output buffer is too small to convert
    # all of the input. Even so, some incomplete sequences may remain in the input
    # until more data is written, which will only trigger an error on close().
    s.outbytesleft[] = 0
    while s.outbytesleft[] < BUFSIZE
        iconv!(s.cd, s.inbuf, s.outbuf, s.inbufptr, s.outbufptr, s.inbytesleft, s.outbytesleft)
        write(s.stream, view(s.outbuf, 1:(BUFSIZE - Int(s.outbytesleft[]))))
    end

    s
end

function close(s::StringEncoder)
    flush(s)
    iconv_reset!(s)
    write(s.stream, view(s.outbuf, 1:(BUFSIZE - Int(s.outbytesleft[]))))
    # Make sure C memory/resources are returned
    finalize(s)
    if s.closestream
        close(s.stream)
    end
    # flush() wasn't able to empty input buffer, which cannot happen with correct data
    s.inbytesleft[] == 0 || throw(IncompleteSequenceError())
end

function write(s::StringEncoder, x::UInt8)
    s.cd == C_NULL && throw(ArgumentError("cannot write to closed StringEncoder"))
    if s.inbytesleft[] >= length(s.inbuf)
        flush(s)
    end
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
"""
function StringDecoder(stream::IO, from::Encoding, to::Encoding=enc"UTF-8")
    cd = iconv_open(String(to), String(from))
    inbuf = Vector{UInt8}(undef, BUFSIZE)
    outbuf = Vector{UInt8}(undef, BUFSIZE)
    s = StringDecoder{typeof(from), typeof(to), typeof(stream)}(stream, false,
                      cd, inbuf, outbuf,
                      Ref{Ptr{UInt8}}(pointer(inbuf)), Ref{Ptr{UInt8}}(pointer(outbuf)),
                      Ref{Csize_t}(0), Ref{Csize_t}(BUFSIZE), 0)
    finalizer(finalize, s)
    s
end

StringDecoder(stream::IO, from::AbstractString, to::Encoding=enc"UTF-8") =
    StringDecoder(stream, Encoding(from), to)
StringDecoder(stream::IO, from::AbstractString, to::AbstractString) =
    StringDecoder(stream, Encoding(from), Encoding(to))

function show(io::IO, s::StringDecoder{F, T}) where {F, T}
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

    # readbytes! performance with SubArray was improved by JuliaLang/julia#36607
    @static if VERSION >= v"1.6.0-DEV.438"
        inbuf_view = view(s.inbuf, Int(s.inbytesleft[]+1):BUFSIZE)
    else
        inbuf_view = unsafe_wrap(Array, pointer(s.inbuf, s.inbytesleft[]+1), BUFSIZE-s.inbytesleft[])
    end
    s.inbytesleft[] += readbytes!(s.stream, inbuf_view)
    iconv!(s.cd, s.inbuf, s.outbuf, s.inbufptr, s.outbufptr, s.inbytesleft, s.outbytesleft)
end

# In order to know whether more data is available, we need to:
# 1) check whether the output buffer contains data
# 2) if not, actually try to fill it (this is the only way to find out whether input
#    data contains only state control sequences which may be converted to nothing)
# 3) if not, reset iconv to initial state, which may generate data
function eof(s::StringDecoder)
    BUFSIZE - s.outbytesleft[] == s.skip &&
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
    s.cd == C_NULL && throw(ArgumentError("cannot read from closed StringDecoder"))
    eof(s) ? throw(EOFError()) : s.outbuf[s.skip+=1]
end

bytesavailable(s::StringDecoder) =
    Int(BUFSIZE - s.outbytesleft[] - s.skip)

function readavailable(s::StringDecoder)
    s.cd == C_NULL && throw(ArgumentError("cannot read from closed StringDecoder"))
    eof(s) # Load more data into buffer if it is empty
    ob = s.outbytesleft[]
    res = s.outbuf[(s.skip+1):(BUFSIZE - ob)]
    s.skip = BUFSIZE - ob
    return res
end

isreadable(s::StringDecoder) = s.cd != C_NULL && isreadable(s.stream)
iswritable(s::StringDecoder) = false

isreadable(s::StringEncoder) = false
iswritable(s::StringEncoder) = s.cd != C_NULL && iswritable(s.stream)


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
              read     :: Union{Bool,Nothing} = nothing,
              write    :: Union{Bool,Nothing} = nothing,
              create   :: Union{Bool,Nothing} = nothing,
              truncate :: Union{Bool,Nothing} = nothing,
              append   :: Union{Bool,Nothing} = nothing)
    if read == true && (write == true || truncate == true || append == true)
        throw(ArgumentError("cannot open encoded text files in read and write/truncate/append modes at the same time"))
    end
    wrap_stream(open(fname, read=read, write=write, create=create, truncate=truncate, append=append),
                enc)
end

function open(fname::AbstractString, enc::Encoding, mode::AbstractString)
    if mode in ("r+", "w+", "a+")
        throw(ArgumentError("cannot open encoded text files in read and write/append modes at the same time"))
    end
    wrap_stream(open(fname, mode), enc)
end

# optimized method adapted from Base but reading as many bytes
# as the buffer contains on each iteration rather than a single one,
# which increases performance dramatically
function readbytes!(s::StringDecoder, b::AbstractArray{UInt8}, nb=length(b))
    olb = lb = length(b)
    nr = 0
    while nr < nb && !eof(s)
        nc = min(nb-nr, BUFSIZE - s.outbytesleft[])
        if nr+nc > lb
            lb = (nr+nc) * 2
            resize!(b, lb)
        end
        copyto!(b, firstindex(b)+nr, s.outbuf, s.skip+1, nc)
        s.skip += nc
        nr += nc
    end
    if lb > olb
        resize!(b, nr) # shrink to just contain input data if was resized
    end
    return nr
end

"""
    read(stream::IO, [nb::Integer,] enc::Encoding)
    read(filename::AbstractString, [nb::Integer,] enc::Encoding)
    read(stream::IO, ::Type{String}, enc::Encoding)
    read(filename::AbstractString, ::Type{String}, enc::Encoding)

Methods to read text in character encoding `enc`. See documentation for corresponding methods
without the `enc` argument for details.
"""
Base.read(s::IO, enc::Encoding) =
    read(StringDecoder(s, enc))
Base.read(filename::AbstractString, enc::Encoding) =
    open(io->read(io, enc), filename)
Base.read(s::IO, nb::Integer, enc::Encoding) =
    read(StringDecoder(s, enc), nb)
Base.read(filename::AbstractString, nb::Integer, enc::Encoding) =
    open(io->read(io, nb, enc), filename)
Base.read(s::IO, ::Type{String}, enc::Encoding) =
    read(StringDecoder(s, enc), String)
Base.read(filename::AbstractString, ::Type{String}, enc::Encoding) =
    open(io->read(io, String, enc), filename)

"""
    readline(stream::IO, enc::Encoding; keep::Bool=false)
    readline(filename::AbstractString, enc::Encoding; keep::Bool=false)

Methods to read text in character encoding `enc`.
"""
readline(s::IO, enc::Encoding; keep::Bool=false) =
    readline(StringDecoder(s, enc), keep=keep)
readline(filename::AbstractString, enc::Encoding; keep::Bool=false) =
    open(io->readline(io, enc, keep=keep), filename)

"""
    readlines(stream::IO, enc::Encoding; keep::Bool=false)
    readlines(filename::AbstractString, enc::Encoding; keep::Bool=false)

Methods to read text in character encoding `enc`.
"""
readlines(s::IO, enc::Encoding; keep::Bool=false) =
    readlines(StringDecoder(s, enc), keep=keep)
readlines(filename::AbstractString, enc::Encoding; keep::Bool=false) =
    open(io->readlines(io, enc, keep=keep), filename)

"""
    readuntil(stream::IO, enc::Encoding, delim; keep::Bool=false)
    readuntil(filename::AbstractString, enc::Encoding, delim; keep::Bool=false)

Methods to read text in character encoding `enc`.
"""
readuntil(s::IO, enc::Encoding, delim; keep::Bool=false) =
    readuntil(StringDecoder(s, enc), delim, keep=keep)
readuntil(filename::AbstractString, enc::Encoding, delim; keep::Bool=false) =
    open(io->readuntil(io, enc, delim, keep=keep), filename)

"""
    eachline(stream::IO, enc::Encoding; keep=false)
    eachline(filename::AbstractString, enc::Encoding; keep=false)

Methods to read text in character encoding `enc`. Decoding is performed on the fly.
"""
eachline(s::IO, enc::Encoding; keep=false) = eachline(StringDecoder(s, enc), keep=keep)
function eachline(filename::AbstractString, enc::Encoding; keep=false)
    s = open(filename, enc)
    Base.EachLine(s, ondone=()->close(s), keep=keep)
end


## Functions to encode/decode strings

"""
    decode([T,] a::AbstractVector{UInt8}, enc)

Convert an array of bytes `a` representing text in encoding `enc` to a string of type `T`.
By default, a `String` is returned.

To `decode` an `s::String` of data in non-UTF-8 encoding, use
`decode(codeunits(s), enc)` to act on the underlying byte array.

`enc` can be specified either as a string or as an `Encoding` object.
The input data `a` can be a `Vector{UInt8}` of bytes, a contiguous
subarray thereof, or the `codeunits` of a `String` (or substring
thereof).
"""
function decode(::Type{T}, a::ByteVector, enc::Encoding) where {T<:AbstractString}
    b = IOBuffer(a)
    try
        T(read(StringDecoder(b, enc, encoding(T))))
    finally
        close(b)
    end
end

decode(::Type{T}, a::ByteVector, enc::AbstractString) where {T<:AbstractString} =
    decode(T, a, Encoding(enc))

decode(a::ByteVector, enc::Union{AbstractString, Encoding}) = decode(String, a, enc)

"""
    encode(s::AbstractString, enc)

Convert string `s` to an array of bytes representing text in encoding `enc`.
`enc` can be specified either as a string or as an `Encoding` object.
"""
encode(s::AbstractString, enc::Encoding) = encode(String(s), enc)
function encode(s::ByteString, enc::Encoding)
    b = IOBuffer()
    p = StringEncoder(b, enc, encoding(typeof(s)))
    write(p, s)
    close(p)
    take!(b)
end

encode(s::AbstractString, enc::AbstractString) = encode(s, Encoding(enc))

function test_encoding(enc::String)
    # We assume that an encoding is supported if it's possible to convert from it to UTF-8:
    cd = ccall((:libiconv_open, libiconv), Ptr{Nothing}, (Cstring, Cstring), enc, "UTF-8")
    if cd == Ptr{Nothing}(-1)
        return false
    else
        iconv_close(cd)
        return true
    end
end

"""
    encodings()

List all encodings supported by `encode`, `decode`, `StringEncoder` and `StringDecoder`
(i.e. by GNU libiconv).

Note that encodings typically appear several times under different names.
In addition to the encodings returned by this function, the empty string (i.e. `""`)
is equivalent to the encoding of the current locale.

Even more encodings may be supported: this can be checked by attempting a conversion.
"""
function encodings()
    filter(test_encoding, encodings_list)
end

end # module
