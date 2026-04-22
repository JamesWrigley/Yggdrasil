# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

include(joinpath("..", "..", "platforms", "macos_sdks.jl"))

name = "libcrystfel"
version = v"0.12.0"

# Collection of sources required to complete build
sources = [
    ArchiveSource("https://gitlab.desy.de/thomas.white/crystfel/-/archive/$(version)/crystfel-$(version).tar.gz", "552cb274de8b3b930c7a574d82e25ae44aeae23e39882d33617bbc6cfdc64d7c"),
    GitSource("https://gitlab.desy.de/thomas.white/fdip.git", "631792e90ed2c3e226dce77bf97917305293ac66")
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir
cd crystfel-*
mv ../fdip subprojects/fdip

LINK_ARGS=''

# Allow undefined symbols in linked libraries. Needed on some platforms because
# our HDF5 is built with MPI support but we don't have MPI as a dependency.
if [[ ${target} != *-apple-* ]]; then
   LINK_ARGS='-Wl,--allow-shlib-undefined'
fi

# Handle argp on glibc/musl
if [[ ${target} == *-musl* || ${target} == *-apple-* ]]; then
    LINK_ARGS="${LINK_ARGS} -largp"
else
    # Ugly hack: we need argp-standalone to build with musl, but when installed
    # alongside glibc it causes compilation errors. So when not on musl we
    # delete the argp.h header so it won't be used.
    rm -f ${includedir}/argp.h
fi

# --wrap-mode: Don't download other sources automatically
meson setup \
      --cross-file=${MESON_TARGET_TOOLCHAIN} \
      --buildtype=release \
      --wrap-mode=nodownload \
      -Dcpp_link_args="${LINK_ARGS}" \
      build

meson compile -C build
meson install -C build

install_license COPYING
"""

sources, script = require_macos_sdk("10.13", sources, script)

# - Windows is not supported because we need forkpty() (and probably other
#   things).
# - Freebsd is not supported because crystfel doesn't recognize libutil.h to get
#   forkpty().
platforms = filter(p -> Sys.islinux(p) || Sys.isapple(p), supported_platforms())

# The products that we will ensure are always built
products = [
    LibraryProduct("libcrystfel", :libcrystfel),
    ExecutableProduct("indexamajig", :indexamajig)
]

# Dependencies that must be installed before this package can be built
dependencies = [
    # Eigen is required for fdip. It's a header-only library so we can get away
    # with it only being a build dependency.
    BuildDependency("Eigen_jll"),
    Dependency("HDF5_jll"),
    Dependency("GSL_jll"),
    Dependency("argp_standalone_jll")
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               julia_compat="1.10",
               # Need this to find the linker on macos
               clang_use_lld=false,
               # GCC version required by HDF5
               preferred_gcc_version=v"12")
