#!/bin/bash
#
# Emacs Dual Build Script
# Supports both autotools and CMake build systems
#

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default build system
BUILD_SYSTEM="cmake"
BUILD_TYPE="Debug"
BUILD_JOBS=""
CLEAN=false
RUN_TESTS=false
AUTOTOOLS_ARGS=""

# Project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Functions
print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build System Selection:
  --autotools, -a           Use autotools build system
  --cmake, -c            Use CMake build system (default)
  --debug, -d              Debug build type
  --release, -r             Release build type
  --relwithdebinfo        Release with debug info build type
  --minsize                Minimum size release build type
  -jN                     Use N parallel jobs (default: auto)
  --clean                  Clean build artifacts before building
  --test, -t               Run tests after build
  --help, -h               Show this help message

Autotools Options:
  --configure-arg=ARG      Pass additional argument to ./configure

Examples:
  $(basename "$0") --cmake --release
  $(basename "$0") --autotools --configure-arg="--with-x-toolkit=gtk3"
  $(basename "$0") -j4 --clean --test

EOF
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --autotools|-a)
            BUILD_SYSTEM="autotools"
            shift
            ;;
        --cmake|-c)
            BUILD_SYSTEM="cmake"
            shift
            ;;
        --debug|-d)
            BUILD_TYPE="Debug"
            shift
            ;;
        --release|-r)
            BUILD_TYPE="Release"
            shift
            ;;
        --relwithdebinfo)
            BUILD_TYPE="RelWithDebInfo"
            shift
            ;;
        --minsize)
            BUILD_TYPE="MinSizeRel"
            shift
            ;;
        -j*)
            BUILD_JOBS="$1"
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --test|-t)
            RUN_TESTS=true
            shift
            ;;
        --configure-arg=*)
            AUTOTOOLS_ARGS="${AUTOTOOLS_ARGS} ${1#*=}"
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Determine number of jobs
if [[ -z "$BUILD_JOBS" ]]; then
    if [[ "$OSTYPE" == "Darwin" ]]; then
        BUILD_JOBS=$(sysctl -n hw.ncpu)
    elif [[ "$OSTYPE" == "Linux" ]]; then
        BUILD_JOBS=$(nproc)
    else
        BUILD_JOBS=1
    fi
fi

# Check if we're in the project root
if [[ ! -f "configure.ac" ]] && [[ ! -f "CMakeLists.txt" ]]; then
    print_error "Not in Emacs project root directory"
    print_error "Expected to find configure.ac or CMakeLists.txt"
    exit 1
fi

# Clean build artifacts if requested
if [[ "$CLEAN" == true ]]; then
    print_status "Cleaning build artifacts..."
    if [[ -d "build-cmake" ]]; then
        rm -rf build-cmake
        print_status "CMake build directory cleaned"
    fi
    if [[ -d "build-autotools" ]]; then
        make distclean 2>/dev/null || true
        print_status "Autotools build artifacts cleaned"
    fi
fi

# Build based on selected system
if [[ "$BUILD_SYSTEM" == "autotools" ]]; then
    # Autotools build
    print_status "Building with Autotools..."
    print_status "Build type: $BUILD_TYPE"
    print_status "Parallel jobs: $BUILD_JOBS"

    # Check if configure exists
    if [[ ! -f "configure" ]]; then
        print_status "Generating configure script..."
        ./autogen.sh || {
            print_error "Failed to generate configure script"
            exit 1
        }
    fi

    # Configure if needed
    if [[ ! -f "Makefile" ]] || [[ "configure" -nt "Makefile" ]]; then
        print_status "Configuring with autotools..."
        ./configure ${AUTOTOOLS_ARGS} || {
            print_error "Configuration failed"
            exit 1
        }
    fi

    # Build
    print_status "Building with autotools..."
    make -j${BUILD_JOBS} || {
        print_error "Build failed"
        exit 1
    fi

    # Run tests if requested
    if [[ "$RUN_TESTS" == true ]]; then
        print_status "Running tests..."
        make check || {
            print_error "Tests failed"
            exit 1
        }
    fi

elif [[ "$BUILD_SYSTEM" == "cmake" ]]; then
    # CMake build
    print_status "Building with CMake..."
    print_status "Build type: $BUILD_TYPE"
    print_status "Parallel jobs: $BUILD_JOBS"

    # Create build directory
    mkdir -p build-cmake
    cd build-cmake

    # Configure with CMake
    print_status "Configuring with CMake..."
    cmake_args=(
        -S "$PROJECT_ROOT"
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    )

    # Add vcpkg toolchain if available
    if [[ -n "$VCPKG_ROOT" ]]; then
        print_status "Using vcpkg toolchain: $VCPKG_ROOT"
        cmake_args+=(-DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake")
    fi

    # Configure
    cmake "${cmake_args[@]}" || {
        print_error "CMake configuration failed"
        exit 1
    }

    # Build
    print_status "Building with CMake..."
    cmake --build . --config "$BUILD_TYPE" || {
        print_error "CMake build failed"
        exit 1
    }

    # Run tests if requested
    if [[ "$RUN_TESTS" == true ]]; then
        print_status "Running tests with CTest..."
        ctest --output-on-failure || {
            print_error "Tests failed"
            exit 1
        }
    fi

    cd "$PROJECT_ROOT"
else
    print_error "Unknown build system: $BUILD_SYSTEM"
    print_usage
    exit 1
fi

# Success message
print_status "Build completed successfully!"
print_status "Build system: $BUILD_SYSTEM"
print_status "Build type: $BUILD_TYPE"
print_status "Output directory: $PROJECT_ROOT/${BUILD_SYSTEM}-build"

if [[ "$BUILD_SYSTEM" == "cmake" ]]; then
    print_status "Executable: $PROJECT_ROOT/build-cmp/bin/emacs"
elif [[ "$BUILD_SYSTEM" == "autotools" ]]; then
    print_status "Executable: $PROJECT_ROOT/src/emacs"
fi
