# Bootstrap Script for Apex Cross-Compilation

## Overview

The `bootstrap.sh` script automates the process of creating a local cross-compiler and using it to cross-compile an Apex base system for a particular target architecture.

## Prerequisites

Before running the bootstrap script, ensure you have the following installed on your build system:

### Required Packages

- GCC and G++ (build toolchain)
- GNU Make
- Bison and Flex
- Texinfo
- Gawk
- Python 3
- Standard build tools: tar, gzip, bzip2, xz, patch, perl
- Alpine Package Keeper (abuild) - Required for building Apex packages

### Alpine Linux Environment

This script is designed to run in an Alpine Linux environment with `abuild` installed. If you're not running Alpine Linux, you can use Docker:

```bash
# Build the Docker image from the repository root
docker build -t apex-bootstrap .

# Run the bootstrap script with Docker (creates output directory if needed)
mkdir -p output
docker run --rm -v $(pwd)/output:/tmp/apex-cross apex-bootstrap ./scripts/bootstrap.sh -a aarch64 -j 8
```

Or use the Alpine container directly:

```bash
docker run -it --rm -v $(pwd):/work alpine:latest
apk add alpine-sdk
cd /work
```

## Usage

### Basic Usage

```bash
./scripts/bootstrap.sh -a <architecture> -j <jobs> -o <output_dir>
```

### Command-Line Options

- `-a ARCH` - Target architecture (default: x86_64)
  - Supported architectures: x86_64, aarch64, armv7, armhf, armv5, armv6, ppc64le, riscv64, loongarch64
- `-j JOBS` - Number of parallel build jobs (default: number of CPU cores)
- `-o OUTPUT` - Output directory for cross-compiler and sysroot (default: /tmp/apex-cross)
- `-c` - Clean build directories before building
- `-n` - Dry run mode - show what would be done without actually building
- `-v` - Verbose output - show detailed execution information
- `-h` - Show help message

### Examples

#### Cross-compile for ARM64 (AArch64)

```bash
./scripts/bootstrap.sh -a aarch64 -j 8 -o /opt/apex-cross-aarch64
```

#### Cross-compile for RISC-V 64-bit

```bash
./scripts/bootstrap.sh -a riscv64 -j 4 -o /opt/apex-cross-riscv64
```

#### Cross-compile with build directory cleanup

```bash
./scripts/bootstrap.sh -a x86_64 -j 12 -o /opt/apex-cross-x86_64 -c
```

#### Dry run to preview build process

```bash
./scripts/bootstrap.sh -a aarch64 -n
```

This will show you what would be built without actually building anything. Useful for:
- Verifying configuration before long builds
- Understanding the build process
- Checking architecture support

#### Verbose mode for debugging

```bash
./scripts/bootstrap.sh -a aarch64 -j 8 -o /opt/apex-cross-aarch64 -v
```

Shows detailed execution information for troubleshooting build issues.

## Build Process

The bootstrap script implements a multi-stage cross-compilation process based on the Linux From Scratch (LFS) methodology:

### Stage 1: Cross-Binutils

Builds the cross-platform assembler and linker for the target architecture. This allows the creation of object files and executables for the target.

### Stage 2: Kernel Headers

Installs Linux kernel headers for the target architecture. These headers are required for building system libraries.

### Stage 3: Cross-GCC Stage 1 (Bootstrap)

Builds a minimal cross-compiler that can compile C code but doesn't have standard libraries. This compiler is used to build the C library.

Configuration: `BOOTSTRAP=nolibc`

### Stage 4: Target Glibc

Builds the GNU C Library (glibc) for the target architecture using the bootstrap compiler. This provides the essential C standard library.

### Stage 5: Cross-GCC Stage 2 (Full)

Rebuilds the cross-compiler with full language support (C, C++, etc.) now that the C library is available.

### Stage 6: Base System

Cross-compiles essential base system packages:
- busybox - Core Unix utilities
- coreutils - GNU core utilities
- bash - Bourne-Again Shell
- Additional essential packages

### Stage 7: Wrapper Scripts

Creates convenience scripts to simplify using the cross-compilation toolchain.

## Output Structure

After successful completion, the output directory will contain:

```
<output_dir>/
├── tools/           # Cross-compilation toolchain
│   └── usr/
│       ├── bin/     # Cross-compiler binaries (e.g., aarch64-apex-linux-gnu-gcc)
│       ├── lib/     # Toolchain libraries
│       └── ...
├── sysroot/         # Target system root
│   ├── usr/
│   │   ├── bin/     # Target binaries
│   │   ├── lib/     # Target libraries
│   │   └── include/ # Target headers
│   └── etc/
├── build/           # Build directories (can be removed after build)
└── sources/         # Downloaded source packages (can be removed)
```

## Using the Cross-Compiler

### Method 1: Add to PATH

```bash
export PATH="/path/to/output/tools/usr/bin:$PATH"
aarch64-apex-linux-gnu-gcc --version
```

### Method 2: Use the Environment Wrapper

```bash
/path/to/output/tools/bin/aarch64-apex-linux-gnu-env gcc --version
```

### Method 3: Cross-compile a Package with abuild

```bash
cd core/some-package
CBUILD=x86_64-pc-linux-gnu \
CHOST=aarch64-apex-linux-gnu \
CTARGET=aarch64-apex-linux-gnu \
CBUILDROOT=/path/to/output/sysroot \
abuild -r
```

## Environment Variables

The script respects and sets the following environment variables:

### Build Configuration
- `CBUILD` - Build system triplet (e.g., x86_64-pc-linux-gnu)
- `CHOST` - Host system triplet (where programs will run)
- `CTARGET` - Target system triplet (for cross-compilers)
- `CBUILDROOT` - Root directory for target system files
- `MAKEFLAGS` - Make parallelization flags

### Customization
- `BASE_PACKAGES` - Space-separated list of base packages to build (default: "busybox coreutils bash")
  - Note: binutils, glibc, and gcc are built in earlier stages as part of the toolchain
  - Example: `BASE_PACKAGES="busybox coreutils bash gawk grep" ./scripts/bootstrap.sh -a aarch64`

## Troubleshooting

### abuild not found

The script requires Alpine's `abuild` tool. Install it with:

```bash
apk add alpine-sdk
```

Or run the script in an Alpine Linux Docker container.

### Build failures

1. Check that all prerequisites are installed
2. Ensure sufficient disk space (recommended: 20+ GB)
3. Try cleaning the build directory with the `-c` flag
4. Check build logs in the respective build directories

### Architecture not supported

Verify that the target architecture is supported by checking:
- The APKBUILD files in core/gcc and core/glibc
- The architecture list in the script's help output

## Time and Resource Requirements

Typical build times (with 8 cores):
- x86_64: 45-90 minutes
- aarch64: 45-90 minutes
- Other architectures: 60-120 minutes

Disk space requirements:
- Minimum: 10 GB
- Recommended: 20+ GB

Memory requirements:
- Minimum: 4 GB RAM
- Recommended: 8+ GB RAM

## Contributing

When modifying the bootstrap script:
1. Test with at least 2 different target architectures
2. Verify that the output cross-compiler can build packages
3. Update documentation for any new options or features
4. Follow shell script best practices (shellcheck)

## References

- [Linux From Scratch](https://www.linuxfromscratch.org/)
- [Cross Linux From Scratch](https://trac.clfs.org/)
- [Alpine Linux Wiki - Cross Compiling](https://wiki.alpinelinux.org/wiki/Cross_compiling)
- [GCC Documentation - Cross Compilation](https://gcc.gnu.org/install/configure.html)

## License

This script is part of the Apex Ports project. See the main LICENSE file for details.
