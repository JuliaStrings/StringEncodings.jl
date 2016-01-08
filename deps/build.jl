using BinDeps

@BinDeps.setup

deps = [
	libiconv = library_dependency("libiconv", aliases = ["libc", "iconv"],
                                  # Check whether libc provides iconv_open (as on Linux)
                                  validate = (n, h) -> Libdl.dlsym_e(h, "iconv_open") != C_NULL)
]

@windows_only begin
    using WinRPM
    provides(WinRPM.RPM, "win_iconv", libiconv, os = :Windows)
end

@osx_only begin
    using Homebrew
    provides(Homebrew.HB, "libiconv", libiconv, os = :Darwin)
end

provides(Sources, URI("http://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.14.tar.gz"), libiconv)

provides(BuildProcess, Autotools(libtarget = "lib/libiconv.la",
                                 installed_libname = "libiconv"*BinDeps.shlib_ext),
         libiconv,
         os = :Unix)

@BinDeps.install Dict(:libiconv => :libiconv_path)
