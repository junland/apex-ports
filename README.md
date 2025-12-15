# apex-ports
ApexOS Ports Repository

## Overview

This repository contains the package definitions (APKBUILD files) for building ApexOS packages. ApexOS uses a package system compatible with Alpine Linux's APK package manager.

## Repository Structure

```
apex-ports/
├── core/           # Core system packages
├── extra/          # Additional packages
└── scripts/        # Build and bootstrap scripts
    └── bootstrap.sh # Cross-compilation bootstrap script
```

## Cross-Compilation

To create a cross-compiler and cross-compile an Apex base system for a different architecture, use the bootstrap script:

```bash
./scripts/bootstrap.sh -a <architecture> -j <jobs> -o <output_dir>
```

Supported architectures:
- x86_64 (64-bit x86)
- aarch64 (ARM 64-bit)
- armv7 / armhf (ARM 32-bit with hard float)
- armv5, armv6 (older ARM variants)
- ppc64le (PowerPC 64-bit little-endian)
- riscv64 (RISC-V 64-bit)
- loongarch64 (LoongArch 64-bit)

For detailed documentation on cross-compilation, see [scripts/README.md](scripts/README.md).

### Using Docker

If you're not running Alpine Linux, you can use Docker to run the bootstrap script:

#### Build the Docker image

```bash
docker build -t apex-bootstrap .
```

#### Run the bootstrap script in Docker

Show help:
```bash
docker run --rm apex-bootstrap
# Or explicitly:
# docker run --rm apex-bootstrap ./scripts/bootstrap.sh -h
```

Cross-compile for ARM64 (mounts local output directory to /tmp/apex-cross, the default output path):
```bash
mkdir -p output
docker run --rm -v $(pwd)/output:/tmp/apex-cross apex-bootstrap ./scripts/bootstrap.sh -a aarch64 -j 8
```

Interactive mode (to explore or debug):
```bash
docker run --rm -it apex-bootstrap sh
```

## Building Packages

### Prerequisites

Building packages requires an Alpine Linux environment with the `alpine-sdk` package:

```bash
apk add alpine-sdk
```

### Building a Single Package

```bash
cd core/<package-name>
abuild -r
```

### Building with Cross-Compilation

```bash
cd core/<package-name>
CBUILD=x86_64-pc-linux-gnu \
CHOST=aarch64-apex-linux-gnu \
CTARGET=aarch64-apex-linux-gnu \
abuild -r
```

## Package Categories

### Core Packages

Essential system packages including:
- **Toolchain**: gcc, binutils, glibc
- **Core Utilities**: busybox, coreutils, bash
- **System Libraries**: glibc, linux-headers
- **Build Tools**: make, cmake, autoconf, automake

### Extra Packages

Additional software packages for specific use cases.

## Contributing

Contributions are welcome! Please ensure that:
1. APKBUILD files follow Alpine Linux packaging standards
2. Patches are properly documented
3. Security fixes are clearly marked
4. Changes are tested on relevant architectures

## License

See LICENSE file for details.
