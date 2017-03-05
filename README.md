# StringEncodings

[![Travis CI Build Status](https://travis-ci.org/nalimilan/StringEncodings.jl.svg?branch=master)](https://travis-ci.org/nalimilan/StringEncodings.jl)
[![AppVeyor Build Status](https://ci.appveyor.com/api/projects/status/3gslhfg91isldnvq?svg=true)](https://ci.appveyor.com/project/nalimilan/stringencodings-jl)
[![Coveralls Coverage Status](https://coveralls.io/repos/nalimilan/StringEncodings.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/nalimilan/StringEncodings.jl?branch=master)
[![Codecov Coverage Status](http://codecov.io/github/nalimilan/StringEncodings.jl/coverage.svg?branch=master)](http://codecov.io/github/nalimilan/StringEncodings.jl?branch=master)

[![Julia 0.4 Status](http://pkg.julialang.org/badges/StringEncodings_0.4.svg)](http://pkg.julialang.org/?pkg=StringEncodings&ver=0.4)
[![Julia 0.5 Status](http://pkg.julialang.org/badges/StringEncodings_0.5.svg)](http://pkg.julialang.org/?pkg=StringEncodings&ver=0.5)
[![Julia 0.6 Status](http://pkg.julialang.org/badges/StringEncodings_0.6.svg)](http://pkg.julialang.org/?pkg=StringEncodings&ver=0.6)

This Julia package provides support for decoding and encoding texts between multiple character encodings. It it currently based on the iconv interface, and supports all major platforms (on Windows, it uses the native OS API via [win_iconv](https://github.com/win-iconv/win-iconv/)). In the future, native Julia support for major encodings will be added.

## Encoding and Decoding Strings
*Encoding* a refers to the process of converting a string (of any `AbstractString` type) to a sequence of bytes represented as a `Vector{UInt8}`. *Decoding* refers to the inverse process.

```julia
julia> using StringEncodings

julia> encode("café", "UTF-16")
10-element Array{UInt8,1}:
 0xff
 0xfe
 0x63
 0x00
 0x61
 0x00
 0x66
 0x00
 0xe9
 0x00

julia> decode(ans, "UTF-16")
"café"
```

Use the `encodings` function to get the list of all supported encodings on the current platform:
```julia
julia> encodings()
1241-element Array{ASCIIString,1}:
 "1026"             
 "1046"             
 "1047"             
 "10646-1:1993"     
 "10646-1:1993/UCS4"
 "437"              
 "500"              
 "500V1"            
 "850"              
 "851"              
 ⋮                  
 "windows-1258"     
 "WINDOWS-1258"     
 "WINDOWS-31J"      
 "windows-874"      
 "WINDOWS-874"      
 "WINDOWS-936"      
 "WINSAMI2"         
 "WS2"              
 "YU"               
```

(Note that many of these are aliases for standard names.)

## The `Encoding` type
In the examples above, the encoding was specified as a standard string. Though, in order to avoid ambiguities in multiple dispatch and to increase performance via type specialization, the package offers a special `Encoding` parametric type. Each parameterization of this type represents a character encoding. The [non-standard string literal](http://docs.julialang.org/en/stable/manual/strings/#man-non-standard-string-literals) `enc` can be used to create an instance of this type, like so: `enc"UTF-16"`.

Since there is no ambiguity, the `encode` and `decode` functions accept either a string or an `Encoding` object. On the other hand, other functions presented below only support the latter to avoid creating conflicts with other packages extending Julia Base methods.

In future versions, the `Encoding` type will allow getting information about character encodings, and will be used to improve the performance of conversions.

## Reading from and Writing to Encoded Text Files
The package also provides several simple methods to deal with files containing encoded text. They extend the equivalent functions from Julia Base, which only support text stored in the UTF-8 encoding.

A method for `open` is provided to write a string under an encoded form to a file:
```julia
julia> path = tempname();

julia> f = open(path, enc"UTF-16", "w");

julia> write(f, "café\nnoël")

julia> close(f); # Essential to complete encoding
```

The contents of the file can then be read back using `readstring` (or `readall` under Julia 0.4):
```julia
julia> readstring(path) # Standard function expects UTF-8
"\U3d83f7c0f\0澊\0n\0o\0迬\0"

julia> readstring(path, enc"UTF-16") # Works when passing the correct encoding
"café\nnoël"
```

Other variants of standard convenience functions are provided:
```julia
julia> readline(path, enc"UTF-16")
"café\n"

julia> readlines(path, enc"UTF-16")
2-element Array{ByteString,1}:
 "café\n"
 "noël"  

julia> for l in eachline(path, enc"UTF-16")
           print(l)
       end
café
noël

julia> readuntil(path, enc"UTF-16", "o")
"café\nno"
```

When performing more complex operations on an encoded text file, it will often be easier to specify the encoding only once when opening it. The resulting I/O stream can then be passed to functions that are unaware of encodings (i.e. that assume UTF-8 text):
```julia
julia> io = open(path, enc"UTF-16");

julia> readstring(io)
"café\nnoël"
```

In particular, this method allows reading encoded comma-separated values (CSV) and other character-delimited text files:
```julia
julia> open(readcsv, path, enc"UTF-16")
2x1 Array{Any,2}:
 "café"
 "noël"
```

## Advanced Usage: `StringEncoder` and `StringDecoder`
The convenience functions presented above are based on the `StringEncoder` and `StringDecoder` types, which wrap I/O streams and offer on-the-fly character encoding conversion facilities. They can be used directly if you need to work with encoded text on an already existing I/O stream. This can be illustrated using an `IOBuffer`:
```julia
julia> b = IOBuffer();

julia> s = StringEncoder(b, "UTF-16");

julia> write(s, "café"); # Encoding happens automatically here

julia> close(s); # Essential to complete encoding

julia> seek(b, 0); # Move to start of buffer

julia> s = StringDecoder(b, "UTF-16");

julia> readstring(s) # Decoding happens automatically here
"café"
```

Do not forget to call `close` on `StringEncoder` and `StringDecoder` objects to finish the encoding process. For `StringEncoder`, this function calls `flush`, which writes any characters still in the buffer, and possibly some control sequences (for stateful encodings). For both `StringEncoder` and `StringDecoder`, `close` checks that there are no incomplete sequences left in the input stream, and raise an `IncompleteSequenceError` if that's the case. It will also free iconv resources immediately, instead of waiting for garbage collection.

Conversion currently raises an error if an invalid byte sequence is encountered in the input, or if some characters cannot be represented in the target enconding. It is not yet possible to ignore such characters or to replace them with a placeholder.
