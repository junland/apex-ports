# Dockerfile for ApexOS Bootstrap Script
# This provides an Alpine Linux environment with all dependencies needed
# to run the cross-compilation bootstrap script.

FROM alpine:latest

# Install required packages for bootstrap script
# - alpine-sdk: Includes abuild and core build tools (gcc, g++, make, etc.)
# - build-base: Additional build essentials
# - bison, flex: Parser generators required by toolchain builds
# - texinfo: Documentation tools needed by some packages
# - gawk: GNU awk for text processing
# - python3: Python interpreter for build scripts
# - tar, gzip, bzip2, xz: Archive utilities
# - patch: For applying patches to source code
# - perl: Perl interpreter for build scripts
# - linux-headers: Linux kernel headers for the build system
RUN apk update && apk add --no-cache \
    alpine-sdk \
    build-base \
    bison \
    flex \
    texinfo \
    gawk \
    python3 \
    tar \
    gzip \
    bzip2 \
    xz \
    patch \
    perl \
    linux-headers

# Create a non-root user for building
# Alpine packages should not be built as root for security
RUN adduser -D -G abuild builder

# Set up abuild key for the builder user
USER builder
RUN abuild-keygen -a -i -n

# Switch back to root to set up working directory
USER root

# Set working directory
WORKDIR /apex-ports

# Copy the entire repository into the container
COPY --chown=builder:abuild . /apex-ports

# Switch to builder user for running builds
USER builder

# Set default command to show help
CMD ["./scripts/bootstrap.sh", "-h"]
