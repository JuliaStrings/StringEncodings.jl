using BinDeps

@BinDeps.setup

# Check for an iconv implementation with the GNU (non-POSIX) behavior:
# EILSEQ is returned when a sequence cannot be converted to target encoding,
# instead of succeeding and only returning the number of invalid conversions
# This non-standard behavior is required to allow replacing invalid sequences
# with a user-defined character.
# Implementations with this behavior include glibc, GNU libiconv (on which Mac
# OS X's is based) and win_iconv.
function validate_iconv(n, h)
    # Needed to check libc
    f = Libdl.dlsym_e(h, "iconv_open")
    f == C_NULL && return false

    cd = ccall(f, Ptr{Void}, (Cstring, Cstring), "ASCII", "UTF-8")
    cd == Ptr{Void}(-1) && return false

    s = "café"
    a = Vector{UInt8}(sizeof(s))
    inbufptr = Ref{Ptr{UInt8}}(pointer(s))
    inbytesleft = Ref{Csize_t}(sizeof(s))
    outbufptr = Ref{Ptr{UInt8}}(pointer(a))
    outbytesleft = Ref{Csize_t}(length(a))
    ret = ccall(Libdl.dlsym_e(h, "iconv"), Csize_t,
                (Ptr{Void}, Ptr{Ptr{UInt8}}, Ref{Csize_t}, Ptr{Ptr{UInt8}}, Ref{Csize_t}),
                cd, inbufptr, inbytesleft, outbufptr, outbytesleft)
    ccall(Libdl.dlsym_e(h, "iconv_close"), Void, (Ptr{Void},), cd) == -1 && return false

    return ret == -1 % Csize_t && Libc.errno() == Libc.EILSEQ
end

libiconv = library_dependency("libiconv", aliases = ["libc", "iconv"],
                              validate = validate_iconv)

if is_windows()
    using WinRPM
    provides(WinRPM.RPM, "win_iconv-dll", libiconv, os = :Windows)
end

provides(Sources,
         URI("http://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.14.tar.gz"),
         libiconv,
         SHA="72b24ded17d687193c3366d0ebe7cde1e6b18f0df8c55438ac95be39e8a30613")

provides(BuildProcess,
         Autotools(libtarget = "lib/libiconv.la",
                   installed_libname = "libiconv"*BinDeps.shlib_ext),
         libiconv,
         os = :Unix)

@BinDeps.install Dict(:libiconv => :libiconv)
