#!/bin/sh
#
# bootstrap.sh - Bootstrap script to create a local cross-compiler and
# cross-compile an apex base system for a particular architecture.
#
# This script implements a multi-stage cross-compilation process:
# 1. Build cross-binutils (assembler and linker)
# 2. Build cross-gcc stage 1 (C compiler only, no libraries)
# 3. Install kernel headers for target architecture
# 4. Build glibc for target architecture
# 5. Build cross-gcc stage 2 (full compiler with C++)
# 6. Cross-compile base system packages
#
# Usage: bootstrap.sh [options]
#   -a ARCH       Target architecture (x86_64, aarch64, etc.)
#   -j JOBS       Number of parallel build jobs (default: nproc)
#   -o OUTPUT     Output directory for cross-compiler and sysroot
#   -c            Clean build directories before building
#   -h            Show this help message
#

set -e

# Script version
VERSION="1.0.0"

# Default configuration
DEFAULT_ARCH="${CTARGET_ARCH:-x86_64}"
DEFAULT_JOBS="$(nproc 2>/dev/null || echo 4)"
DEFAULT_OUTPUT="/tmp/apex-cross"
CLEAN_BUILD=0
DRY_RUN=0
VERBOSE=0

# Parse command line arguments
ARCH="$DEFAULT_ARCH"
JOBS="$DEFAULT_JOBS"
OUTPUT="$DEFAULT_OUTPUT"

usage() {
	cat <<EOF
Bootstrap Script for Apex Cross-Compilation v${VERSION}

Usage: $0 [options]

Options:
  -a ARCH       Target architecture (default: ${DEFAULT_ARCH})
                Supported: x86_64, aarch64, armv7, armhf, armv5, armv6, 
                           ppc64le, riscv64, loongarch64
  -j JOBS       Number of parallel build jobs (default: ${DEFAULT_JOBS})
  -o OUTPUT     Output directory for cross-tools (default: ${DEFAULT_OUTPUT})
  -c            Clean build directories before building
  -n            Dry run - show what would be done without building
  -v            Verbose output
  -h            Show this help message

Example:
  $0 -a aarch64 -j 8 -o /opt/apex-cross

Environment Variables:
  CBUILD        Build system triplet (auto-detected)
  CHOST         Host system triplet (auto-detected)
  CTARGET       Target system triplet (derived from ARCH)

EOF
	exit 0
}

while getopts "a:j:o:cnvh" opt; do
	case "$opt" in
		a) ARCH="$OPTARG" ;;
		j) JOBS="$OPTARG" ;;
		o) OUTPUT="$OPTARG" ;;
		c) CLEAN_BUILD=1 ;;
		n) DRY_RUN=1 ;;
		v) VERBOSE=1 ;;
		h) usage ;;
		*) usage ;;
	esac
done

# Logging functions
log() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_info() {
	log "INFO: $*"
}

log_error() {
	log "ERROR: $*" >&2
}

log_warn() {
	log "WARNING: $*"
}

die() {
	log_error "$*"
	exit 1
}

# Execute command with dry-run support
run_cmd() {
	if [ "$DRY_RUN" -eq 1 ]; then
		log_info "[DRY RUN] Would execute: $*"
		return 0
	fi
	
	if [ "$VERBOSE" -eq 1 ]; then
		log_info "Executing: $*"
	fi
	
	"$@"
}

# Architecture mapping and validation
get_target_triplet() {
	local arch="$1"
	case "$arch" in
		x86_64)
			echo "x86_64-apex-linux-gnu"
			;;
		aarch64)
			echo "aarch64-apex-linux-gnu"
			;;
		armv7|armhf)
			echo "armv7-apex-linux-gnueabihf"
			;;
		armv5)
			echo "armv5-apex-linux-gnueabi"
			;;
		armv6)
			echo "armv6-apex-linux-gnueabihf"
			;;
		ppc64le)
			echo "powerpc64le-apex-linux-gnu"
			;;
		riscv64)
			echo "riscv64-apex-linux-gnu"
			;;
		loongarch64)
			echo "loongarch64-apex-linux-gnu"
			;;
		*)
			die "Unsupported architecture: $arch"
			;;
	esac
}

# Detect build system
detect_build_system() {
	if command -v gcc >/dev/null 2>&1; then
		gcc -dumpmachine
	else
		die "GCC not found. Please install build-essential or equivalent."
	fi
}

# Check prerequisites
check_prerequisites() {
	log_info "Checking prerequisites..."
	
	local missing=""
	for cmd in gcc g++ make bison flex texinfo gawk python3 tar gzip bzip2 xz patch perl; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing="$missing $cmd"
		fi
	done
	
	if [ -n "$missing" ]; then
		die "Missing required tools:$missing"
	fi
	
	log_info "All prerequisites satisfied"
}

# Setup directory structure
setup_directories() {
	log_info "Setting up directory structure in $OUTPUT..."
	
	mkdir -p "$OUTPUT"/{sources,build,tools,sysroot}
	mkdir -p "$OUTPUT/sysroot"/{usr/{bin,lib,include},etc,var}
	
	# Create symlinks for compatibility
	if [ ! -e "$OUTPUT/sysroot/bin" ]; then
		ln -sf usr/bin "$OUTPUT/sysroot/bin"
	fi
	if [ ! -e "$OUTPUT/sysroot/lib" ]; then
		ln -sf usr/lib "$OUTPUT/sysroot/lib"
	fi
	
	if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "aarch64" ]; then
		mkdir -p "$OUTPUT/sysroot/usr/lib64"
		if [ ! -e "$OUTPUT/sysroot/lib64" ]; then
			ln -sf usr/lib64 "$OUTPUT/sysroot/lib64"
		fi
	fi
	
	log_info "Directory structure created"
}

# Build cross-binutils
build_binutils() {
	log_info "Building cross-binutils for $CTARGET..."
	
	local src_dir="$SCRIPT_DIR/../core/binutils"
	local build_dir="$OUTPUT/build/binutils"
	
	if [ ! -d "$src_dir" ]; then
		die "Binutils source directory not found: $src_dir"
	fi
	
	# Clean if requested
	if [ "$CLEAN_BUILD" -eq 1 ] && [ -d "$build_dir" ]; then
		log_info "Cleaning binutils build directory"
		rm -rf "$build_dir"
	fi
	
	mkdir -p "$build_dir"
	cd "$build_dir"
	
	log_info "Building binutils with BOOTSTRAP=nolibc CBUILD=$CBUILD CHOST=$CBUILD CTARGET=$CTARGET..."
	
	# Use abuild if available, otherwise manual build
	if command -v abuild >/dev/null 2>&1; then
		export BOOTSTRAP=nolibc
		export CBUILD="$CBUILD"
		export CHOST="$CBUILD"
		export CTARGET="$CTARGET"
		export DESTDIR="$OUTPUT/tools"
		
		cd "$src_dir"
		abuild -r || die "Failed to build binutils"
	else
		log_warn "abuild not available, cross-compilation requires Alpine build environment"
		die "Please run this script in an Alpine Linux environment with abuild installed"
	fi
	
	log_info "Cross-binutils built successfully"
}

# Install kernel headers
install_kernel_headers() {
	log_info "Installing kernel headers for $CTARGET..."
	
	local src_dir="$SCRIPT_DIR/../core/linux-headers"
	
	if [ ! -d "$src_dir" ]; then
		die "Linux headers source directory not found: $src_dir"
	fi
	
	if command -v abuild >/dev/null 2>&1; then
		export BOOTSTRAP=nolibc
		export CBUILD="$CBUILD"
		export CHOST="$CBUILD"
		export CTARGET="$CTARGET"
		export DESTDIR="$OUTPUT/sysroot"
		
		cd "$src_dir"
		abuild -r || die "Failed to install kernel headers"
	else
		die "abuild required for building packages"
	fi
	
	log_info "Kernel headers installed successfully"
}

# Build GCC stage 1 (bootstrap compiler, no libc)
build_gcc_stage1() {
	log_info "Building cross-gcc stage 1 for $CTARGET..."
	
	local src_dir="$SCRIPT_DIR/../core/gcc"
	local build_dir="$OUTPUT/build/gcc-stage1"
	
	if [ ! -d "$src_dir" ]; then
		die "GCC source directory not found: $src_dir"
	fi
	
	if [ "$CLEAN_BUILD" -eq 1 ] && [ -d "$build_dir" ]; then
		log_info "Cleaning gcc stage1 build directory"
		rm -rf "$build_dir"
	fi
	
	mkdir -p "$build_dir"
	
	if command -v abuild >/dev/null 2>&1; then
		export BOOTSTRAP=nolibc
		export CBUILD="$CBUILD"
		export CHOST="$CBUILD"
		export CTARGET="$CTARGET"
		export CBUILDROOT="$OUTPUT/sysroot"
		export DESTDIR="$OUTPUT/tools"
		
		cd "$src_dir"
		abuild -r || die "Failed to build gcc stage 1"
	else
		die "abuild required for building packages"
	fi
	
	log_info "Cross-gcc stage 1 built successfully"
}

# Build glibc for target
build_glibc() {
	log_info "Building glibc for $CTARGET..."
	
	local src_dir="$SCRIPT_DIR/../core/glibc"
	
	if [ ! -d "$src_dir" ]; then
		die "Glibc source directory not found: $src_dir"
	fi
	
	if command -v abuild >/dev/null 2>&1; then
		export BOOTSTRAP=nolibc
		export CBUILD="$CBUILD"
		export CHOST="$CTARGET"
		export CTARGET="$CTARGET"
		export CBUILDROOT="$OUTPUT/sysroot"
		export DESTDIR="$OUTPUT/sysroot"
		export PATH="$OUTPUT/tools/usr/bin:$PATH"
		
		cd "$src_dir"
		abuild -r || die "Failed to build glibc"
	else
		die "abuild required for building packages"
	fi
	
	log_info "Glibc built successfully"
}

# Build GCC stage 2 (full compiler with C++)
build_gcc_stage2() {
	log_info "Building cross-gcc stage 2 (full) for $CTARGET..."
	
	local src_dir="$SCRIPT_DIR/../core/gcc"
	local build_dir="$OUTPUT/build/gcc-stage2"
	
	if [ "$CLEAN_BUILD" -eq 1 ] && [ -d "$build_dir" ]; then
		log_info "Cleaning gcc stage2 build directory"
		rm -rf "$build_dir"
	fi
	
	mkdir -p "$build_dir"
	
	if command -v abuild >/dev/null 2>&1; then
		unset BOOTSTRAP
		export CBUILD="$CBUILD"
		export CHOST="$CBUILD"
		export CTARGET="$CTARGET"
		export CBUILDROOT="$OUTPUT/sysroot"
		export DESTDIR="$OUTPUT/tools"
		export PATH="$OUTPUT/tools/usr/bin:$PATH"
		
		cd "$src_dir"
		abuild -r || die "Failed to build gcc stage 2"
	else
		die "abuild required for building packages"
	fi
	
	log_info "Cross-gcc stage 2 built successfully"
}

# Build base system packages
build_base_system() {
	log_info "Building base system packages for $CTARGET..."
	
	# Default base packages (can be overridden via BASE_PACKAGES env var)
	# Note: binutils, glibc, and gcc are already built in earlier stages,
	# but may need to be rebuilt for the target system
	local packages="${BASE_PACKAGES:-busybox coreutils bash}"
	local failed_packages=""
	local built_packages=""
	
	export CBUILD="$CBUILD"
	export CHOST="$CTARGET"
	export CTARGET="$CTARGET"
	export CBUILDROOT="$OUTPUT/sysroot"
	export DESTDIR="$OUTPUT/sysroot"
	export PATH="$OUTPUT/tools/usr/bin:$PATH"
	export PKG_CONFIG_PATH="$OUTPUT/sysroot/usr/lib/pkgconfig"
	export PKG_CONFIG_SYSROOT_DIR="$OUTPUT/sysroot"
	
	for pkg in $packages; do
		log_info "Building package: $pkg"
		local pkg_dir="$SCRIPT_DIR/../core/$pkg"
		
		if [ ! -d "$pkg_dir" ]; then
			log_warn "Package directory not found: $pkg_dir, skipping"
			failed_packages="$failed_packages $pkg"
			continue
		fi
		
		if command -v abuild >/dev/null 2>&1; then
			cd "$pkg_dir"
			if abuild -r; then
				built_packages="$built_packages $pkg"
				log_info "Package $pkg built successfully"
			else
				log_warn "Failed to build package: $pkg"
				failed_packages="$failed_packages $pkg"
			fi
		fi
	done
	
	log_info "Base system package build summary:"
	log_info "  Successfully built: $built_packages"
	if [ -n "$failed_packages" ]; then
		log_warn "  Failed to build: $failed_packages"
		log_warn "  The base system may be incomplete"
	fi
}

# Create toolchain wrapper scripts
create_wrappers() {
	log_info "Creating toolchain wrapper scripts..."
	
	# Validate CTARGET to prevent path traversal
	case "$CTARGET" in
		*/* | *.* | *..*)
			die "Invalid CTARGET value: $CTARGET"
			;;
	esac
	
	local wrapper_dir="$OUTPUT/tools/bin"
	mkdir -p "$wrapper_dir"
	
	# Create wrapper for easier cross-compilation
	cat > "$wrapper_dir/${CTARGET}-env" <<EOF
#!/bin/sh
# Environment setup for cross-compilation to $CTARGET
export CBUILD="$CBUILD"
export CHOST="$CTARGET"
export CTARGET="$CTARGET"
export CBUILDROOT="$OUTPUT/sysroot"
export PATH="$OUTPUT/tools/usr/bin:\$PATH"
export PKG_CONFIG_PATH="$OUTPUT/sysroot/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$OUTPUT/sysroot"
export CC="${CTARGET}-gcc"
export CXX="${CTARGET}-g++"
export AR="${CTARGET}-ar"
export AS="${CTARGET}-as"
export LD="${CTARGET}-ld"
export RANLIB="${CTARGET}-ranlib"
export STRIP="${CTARGET}-strip"

exec "\$@"
EOF
	chmod +x "$wrapper_dir/${CTARGET}-env"
	
	log_info "Wrapper scripts created in $wrapper_dir"
}

# Main build process
main() {
	log_info "=== Apex Cross-Compilation Bootstrap v${VERSION} ==="
	log_info "Target Architecture: $ARCH"
	log_info "Parallel Jobs: $JOBS"
	log_info "Output Directory: $OUTPUT"
	
	if [ "$DRY_RUN" -eq 1 ]; then
		log_info "DRY RUN MODE - No actual building will occur"
	fi
	
	if [ "$VERBOSE" -eq 1 ]; then
		log_info "VERBOSE MODE - Detailed output enabled"
	fi
	
	# Get script directory
	SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
	
	# Detect build system
	CBUILD="$(detect_build_system)"
	CHOST="$CBUILD"
	CTARGET="$(get_target_triplet "$ARCH")"
	
	log_info "Build System: $CBUILD"
	log_info "Host System: $CHOST"
	log_info "Target System: $CTARGET"
	
	# Check prerequisites
	if [ "$DRY_RUN" -eq 0 ]; then
		check_prerequisites
	else
		log_info "[DRY RUN] Would check prerequisites"
	fi
	
	# Setup directories
	if [ "$DRY_RUN" -eq 0 ]; then
		setup_directories
	else
		log_info "[DRY RUN] Would setup directories in $OUTPUT"
	fi
	
	# Export common variables
	export MAKEFLAGS="-j${JOBS}"
	export CBUILD CHOST CTARGET
	
	# Build process
	log_info "=== Stage 1: Cross-Binutils ==="
	if [ "$DRY_RUN" -eq 0 ]; then
		build_binutils
	else
		log_info "[DRY RUN] Would build cross-binutils"
	fi
	
	log_info "=== Stage 2: Kernel Headers ==="
	if [ "$DRY_RUN" -eq 0 ]; then
		install_kernel_headers
	else
		log_info "[DRY RUN] Would install kernel headers"
	fi
	
	log_info "=== Stage 3: Cross-GCC Stage 1 ==="
	if [ "$DRY_RUN" -eq 0 ]; then
		build_gcc_stage1
	else
		log_info "[DRY RUN] Would build cross-gcc stage 1"
	fi
	
	log_info "=== Stage 4: Target Glibc ==="
	if [ "$DRY_RUN" -eq 0 ]; then
		build_glibc
	else
		log_info "[DRY RUN] Would build target glibc"
	fi
	
	log_info "=== Stage 5: Cross-GCC Stage 2 ==="
	if [ "$DRY_RUN" -eq 0 ]; then
		build_gcc_stage2
	else
		log_info "[DRY RUN] Would build cross-gcc stage 2"
	fi
	
	log_info "=== Stage 6: Base System ==="
	if [ "$DRY_RUN" -eq 0 ]; then
		build_base_system
	else
		log_info "[DRY RUN] Would build base system packages"
	fi
	
	log_info "=== Stage 7: Create Wrappers ==="
	if [ "$DRY_RUN" -eq 0 ]; then
		create_wrappers
	else
		log_info "[DRY RUN] Would create wrapper scripts"
	fi
	
	# Summary
	log_info "=== Bootstrap Complete ==="
	
	if [ "$DRY_RUN" -eq 1 ]; then
		log_info "DRY RUN COMPLETED - No files were modified"
		log_info ""
		log_info "To actually build, run without the -n flag:"
		log_info "  $0 -a $ARCH -j $JOBS -o $OUTPUT"
	else
		log_info "Cross-compiler location: $OUTPUT/tools"
		log_info "Target sysroot location: $OUTPUT/sysroot"
		log_info ""
		log_info "To use the cross-compiler, run:"
		log_info "  export PATH=\"$OUTPUT/tools/usr/bin:\$PATH\""
		log_info "Or use the wrapper:"
		log_info "  $OUTPUT/tools/bin/${CTARGET}-env <command>"
		log_info ""
		log_info "To cross-compile a package:"
		log_info "  cd <package-dir>"
		log_info "  CBUILD=$CBUILD CHOST=$CTARGET CTARGET=$CTARGET CBUILDROOT=$OUTPUT/sysroot abuild -r"
	fi
}

# Run main function
main "$@"
