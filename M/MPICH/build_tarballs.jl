using BinaryBuilder, Pkg
using Base.BinaryPlatforms
const YGGDRASIL_DIR = "../.."
include(joinpath(YGGDRASIL_DIR, "platforms", "mpi.jl"))

name = "MPICH"
version = v"4.3.1"

sources = [
    ArchiveSource("https://www.mpich.org/static/downloads/$(version)/mpich-$(version).tar.gz",
                  "acc11cb2bdc69678dc8bba747c24a28233c58596f81f03785bf2b7bb7a0ef7dc"),
    DirectorySource("bundled"),
]

script = raw"""
################################################################################
# Install MPICH
################################################################################

# Enter the funzone
cd ${WORKSPACE}/srcdir/mpich*

# MPICH does not include `<pthread_np.h>` on FreeBSD: <https://github.com/pmodels/mpich/issues/6821>.
# (The MPICH developers say that this is a bug in MPICH and that
# `<pthread_np.h>` should not actually be used on FreeBSD.)
atomic_patch -p1 ${WORKSPACE}/srcdir/patches/pthread_np.patch

# - Do not install doc and man files which contain files which clashing names on
#   case-insensitive file systems:
#   * https://github.com/JuliaPackaging/Yggdrasil/pull/315
#   * https://github.com/JuliaPackaging/Yggdrasil/issues/6344
# - `--enable-fast=all,O3` leads to very long compile times for the
#   file `src/mpi/coll/mpir_coll.c`. It seems we need to avoid
#   `alwaysinline`.
# - We need to use `ch3` because `ch4` breaks on some systems, e.g. on
#   x86_64 macOS. See
#   <https://github.com/JuliaPackaging/Yggdrasil/pull/10249#discussion_r1975948816> for a brief
#   discussion.
configure_flags=(
    --build=${MACHTYPE}
    --disable-dependency-tracking
    --disable-doc
    --enable-fast=ndebug,O3
    --enable-static=no
    --host=${target}
    --prefix=${prefix}
    --with-device=ch3
    --with-hwloc=${prefix}
)

# Define some obscure undocumented variables needed for cross compilation of
# the Fortran bindings.  See for example
# * https://stackoverflow.com/q/56759636/2442087
# * https://github.com/pmodels/mpich/blob/d10400d7a8238dc3c8464184238202ecacfb53c7/doc/installguide/cfile
export CROSS_F77_SIZEOF_INTEGER=4
export CROSS_F77_SIZEOF_REAL=4
export CROSS_F77_SIZEOF_DOUBLE_PRECISION=8
export CROSS_F77_SIZEOF_LOGICAL=4
export CROSS_F77_TRUE_VALUE=1
export CROSS_F77_FALSE_VALUE=0

if [[ ${nbits} == 32 ]]; then
    export CROSS_F90_ADDRESS_KIND=4
else
    export CROSS_F90_ADDRESS_KIND=8
fi
export CROSS_F90_OFFSET_KIND=8
export CROSS_F90_INTEGER_KIND=4
export CROSS_F90_INTEGER_MODEL=9
export CROSS_F90_REAL_MODEL=6,37
export CROSS_F90_DOUBLE_MODEL=15,307
export CROSS_F90_ALL_INTEGER_MODELS=2,1,4,2,9,4,18,8,
export CROSS_F90_INTEGER_MODEL_MAP={2,1,1},{4,2,2},{9,4,4},{18,8,8},

if [[ "${target}" == i686-linux-musl ]]; then
    # Our `i686-linux-musl` platform is a bit rotten: it can run C programs,
    # but not C++ or Fortran.  `configure` runs a C program to determine
    # whether it's cross-compiling or not, but when it comes to running
    # Fortran programs, it fails.  In addition, `configure` ignores the
    # above exported variables if it believes it's doing a native build.
    # Small hack: edit `configure` script to force `cross_compiling` to be
    # always "yes".
    sed -i 's/cross_compiling=no/cross_compiling=yes/g' configure
    configure_flags+=(ac_cv_sizeof_bool="1")
fi

if [[ "${target}" == aarch64-apple-* ]]; then
    configure_flags+=(
        FFLAGS=-fallow-argument-mismatch
        FCFLAGS=-fallow-argument-mismatch
    )
fi

./configure "${configure_flags[@]}"

# Remove empty `-l` flags from libtool
# (Why are they there? They should not be.)
# Run the command several times to handle multiple (overlapping) occurrences.
sed -i 's/"-l /"/g;s/ -l / /g;s/-l"/"/g' libtool
sed -i 's/"-l /"/g;s/ -l / /g;s/-l"/"/g' libtool
sed -i 's/"-l /"/g;s/ -l / /g;s/-l"/"/g' libtool

# Build the library
make -j${nproc}

# Install the library
make install

# Install the license
install_license $WORKSPACE/srcdir/mpich*/COPYRIGHT
"""

augment_platform_block = """
    using Base.BinaryPlatforms
    $(MPI.augment)
    augment_platform!(platform::Platform) = augment_mpi!(platform)
"""

platforms = supported_platforms()
platforms = expand_gfortran_versions(platforms)

filter!(!Sys.iswindows, platforms)

# Add `mpi+mpich` platform tag
for p in platforms
    p["mpi"] = "MPICH"
end

products = [
    # MPICH
    LibraryProduct("libmpicxx", :libmpicxx),
    LibraryProduct("libmpifort", :libmpifort),
    LibraryProduct("libmpi", :libmpi),
    ExecutableProduct("mpiexec", :mpiexec),
]

dependencies = [
    Dependency(PackageSpec(name="CompilerSupportLibraries_jll", uuid="e66e0078-7015-5450-92f7-15fbd957f2ae")),
    Dependency("Hwloc_jll"; compat="2.12.0"),
    RuntimeDependency(PackageSpec(name="MPIPreferences", uuid="3da0fdf6-3ccc-4f1b-acd9-58baa6c99267");
                      compat="0.1", top_level=true),
]

# Build the tarballs.
# We use GCC 5 to ensure Fortran module files are readable by all `libgfortran3` architectures. GCC 4 would use an older format.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               augment_platform_block, julia_compat="1.6", clang_use_lld=false, preferred_gcc_version=v"5")
