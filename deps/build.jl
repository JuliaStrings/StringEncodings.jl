using BinDeps

@BinDeps.setup

libiconv = library_dependency("libiconv", aliases = ["libc", "iconv"],
                              # Check whether libc provides iconv_open (as on Linux)
                              validate = (n, h) -> Libdl.dlsym_e(h, "iconv_open") != C_NULL)

@windows_only begin
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
