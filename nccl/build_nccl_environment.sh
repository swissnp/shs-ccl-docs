#!/bin/bash
# SPDX-FileCopyrightText: Copyright Hewlett Packard Enterprise Development LP
# SPDX-License-Identifier: MIT

# Hewlett Packard Enterprise 2025
# Isa Wazirzada, Ryan Hankins
set -e
set -o pipefail

# Defaults
BASE_DIR=$(pwd)
LIBFABRIC_PATH="/opt/cray/libfabric/1.22.0"
PARALLELISM=16
NCCL_VERSION="593de54e52679b51428571c13271e2ea9f91b1b1"
AWS_OFI_NCCL_VERSION="v1.19.0"
SKIP_CLONE=false
SKIP_TESTS=false
LOG_DIR=""
NCCL_SRC_DIR=""

# Help
usage() {
    echo "A utility to build a NCCL runtime environment to run NCCL Tests on a Slingshot network."
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -b, --base-dir <path>         Base directory for builds (default: current directory)"
    echo "  -l, --libfabric-path <path>   Path to libfabric (default: $LIBFABRIC_PATH)"
    echo "  -p, --parallelism <threads>   Number of threads for parallel builds (default: $PARALLELISM)"
    echo "  -n, --nccl-version <ref>      NCCL git ref to build (tag, branch, or commit; default: $NCCL_VERSION)"
    echo "  -a, --aws-version <version>   AWS OFI NCCL plugin version to build (default: $AWS_OFI_NCCL_VERSION)"
    echo "  --log-dir <path>              Directory to save the build log file (default: <base-dir>/logs)"
    echo "  --skip-clone                  Skip cloning repositories (use existing directories)"
    echo "  --skip-tests                  Skip building NCCL Tests"
    echo "  -h, --help                    Give a little help"
    exit 0
}


ARGS=$(getopt -o b:l:p:n:a:h --long base-dir:,libfabric-path:,parallelism:,nccl-version:,aws-version:,log-dir:,skip-clone,skip-tests,help -n "$0" -- "$@")
if [ $? -ne 0 ]; then usage; fi
eval set -- "$ARGS"

while true; do
    case "$1" in
        -b|--base-dir) BASE_DIR="$2"; shift 2 ;;
        -l|--libfabric-path) LIBFABRIC_PATH="$2"; shift 2 ;;
        -p|--parallelism) PARALLELISM="$2"; shift 2 ;;
        -n|--nccl-version) NCCL_VERSION="$2"; shift 2 ;;
        -a|--aws-version) AWS_OFI_NCCL_VERSION="$2"; shift 2 ;;
        --log-dir) LOG_DIR="$2"; shift 2 ;;
        --skip-clone) SKIP_CLONE=true; shift ;;
        --skip-tests) SKIP_TESTS=true; shift ;;
        -h|--help) usage ;;
        --) shift; break ;;
        *) echo "Unexpected option: $1"; usage ;;
    esac
done

if [ -z "$LOG_DIR" ]; then
    LOG_DIR="$BASE_DIR/logs"
fi

if [ -z "$NCCL_SRC_DIR" ]; then
    NCCL_SRC_DIR="$BASE_DIR/nccl-src"
fi

AWS_OFI_CC=${AWS_OFI_CC:-cc}
AWS_OFI_CXX=${AWS_OFI_CXX:-CC}
AWS_OFI_CFLAGS=${AWS_OFI_CFLAGS:-}
AWS_OFI_CXXFLAGS=${AWS_OFI_CXXFLAGS:--Wno-error=vla-cxx-extension}

ensure_local_git_ref() {
    local repo_path="$1"
    local ref="$2"
    local repo_name="$3"

    cd "$repo_path"

    if git rev-parse --verify "${ref}^{commit}" >/dev/null 2>&1; then
        git checkout "$ref" || { echo "Failed to checkout $repo_name ref $ref"; exit 1; }
        return
    fi

    if [ "$SKIP_CLONE" = true ]; then
        echo "Error: $repo_name ref $ref is not available in the local checkout at $repo_path."
        echo "This run is in local-only mode (--skip-clone), which is required on offline compute nodes."
        echo "Fetch the ref on a node with internet access, then resubmit the Slurm job."
        exit 1
    fi

    git fetch origin --tags --quiet || { echo "Failed to fetch $repo_name refs"; exit 1; }
    git checkout "$ref" || { echo "Failed to checkout $repo_name ref $ref"; exit 1; }
}

write_runtime_env_files() {
    local runtime_env_file="$BASE_DIR/setup_nccl_runtime_env.sh"
    local all_reduce_wrapper="$BASE_DIR/run_all_reduce_perf.sh"

    cat > "$runtime_env_file" <<EOF
#!/bin/bash
# Source this file before running NCCL test binaries built by
# build_nccl_environment.sh so they load the matching NCCL runtime.
export NCCL_HOME="$NCCL_HOME"
export AWS_OFI_NCCL_HOME="$AWS_OFI_NCCL_HOME"
export NCCL_TESTS_HOME="$NCCL_TESTS_HOME"
export LD_LIBRARY_PATH="$AWS_OFI_NCCL_HOME:$NCCL_HOME/lib:\${LD_LIBRARY_PATH}"
export PATH="$NCCL_TESTS_HOME:\${PATH}"
EOF
    chmod +x "$runtime_env_file"

    cat > "$all_reduce_wrapper" <<EOF
#!/bin/bash
set -e
source "$runtime_env_file"
exec "$NCCL_TESTS_HOME/all_reduce_perf" "\$@"
EOF
    chmod +x "$all_reduce_wrapper"
}


TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="${LOG_DIR}/build_${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"

# Redirecting stdout/stderr to a log file
exec > >(tee "$LOG_FILE") 2>&1

echo "============================="
echo "Build log: $LOG_FILE"
echo "============================="

NCCL_HOME="$NCCL_SRC_DIR/build"
AWS_OFI_NCCL_HOME="$BASE_DIR/aws-ofi-nccl/src/.libs"
NCCL_TESTS_HOME="$BASE_DIR/nccl-tests/build"

echo "============================="
echo "Starting NCCL environment setup..."
echo "Base Directory: $BASE_DIR"
echo "Log Directory: $LOG_DIR"
echo "NCCL Source Directory: $NCCL_SRC_DIR"
echo "Libfabric Path: $LIBFABRIC_PATH"
echo "Parallelism: $PARALLELISM"
echo "NCCL Version: $NCCL_VERSION"
echo "AWS OFI NCCL Plugin Version: $AWS_OFI_NCCL_VERSION"
echo "AWS OFI NCCL C Compiler: $AWS_OFI_CC"
echo "AWS OFI NCCL C++ Compiler: $AWS_OFI_CXX"
echo "AWS OFI NCCL CFLAGS: $AWS_OFI_CFLAGS"
echo "AWS OFI NCCL CXXFLAGS: $AWS_OFI_CXXFLAGS"
echo "Skip Cloning: $SKIP_CLONE"
echo "Skip NCCL Tests: $SKIP_TESTS"
echo "============================="



# Preflight Checks
echo "Validating environment variables..."
if [ -z "$CUDA_HOME" ]; then
    echo "Error: CUDA_HOME is not set. Ensure the CUDA toolkit module is loaded correctly."
    exit 1
fi

if [ -z "$MPICH_DIR" ]; then
    echo "Error: MPICH_DIR is not set. Ensure the cray-mpich-abi module is loaded correctly."
    exit 1
fi

# Clone and build NCCL
if [ "$SKIP_CLONE" = false ]; then
    echo "Cloning and building NCCL..."
    if [ ! -d "$NCCL_SRC_DIR" ]; then
        git clone https://github.com/NVIDIA/nccl.git "$NCCL_SRC_DIR" || { echo "Failed to clone NCCL repository"; exit 1; }
    fi
fi
if [ ! -d "$NCCL_SRC_DIR/.git" ]; then
    echo "Error: NCCL source directory $NCCL_SRC_DIR does not contain a git checkout. Re-run without --skip-clone or fix the directory."
    exit 1
fi
ensure_local_git_ref "$NCCL_SRC_DIR" "$NCCL_VERSION" "NCCL"
cd "$NCCL_SRC_DIR"
make -j "$PARALLELISM" || { echo "Failed to build NCCL"; exit 1; }
cd ..

# Clone and build the AWS OFI NCCL plugin
if [ "$SKIP_CLONE" = false ]; then
    echo "Cloning and building AWS OFI NCCL plugin..."
    if [ ! -d "aws-ofi-nccl" ]; then
        git clone https://github.com/aws/aws-ofi-nccl.git || { echo "Failed to clone AWS OFI NCCL repository"; exit 1; } && git -C aws-ofi-nccl fetch --tags --quiet
    fi
fi
if [ ! -d "aws-ofi-nccl/.git" ]; then
    echo "Error: aws-ofi-nccl source directory $BASE_DIR/aws-ofi-nccl does not contain a git checkout."
    echo "Populate it on a node with internet access, or re-run without --skip-clone from a node that can reach GitHub."
    exit 1
fi
ensure_local_git_ref "$BASE_DIR/aws-ofi-nccl" "$AWS_OFI_NCCL_VERSION" "AWS OFI NCCL"
cd aws-ofi-nccl
env LANG=C LC_ALL=C ./autogen.sh || { echo "Failed to run autogen.sh for AWS OFI NCCL"; exit 1; }
# Run configure with a clean compiler environment so inherited flags do not
# break Autoconf header checks such as limits.h on HPC systems.
env -u CPATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH -u CPPFLAGS -u CFLAGS -u CXXFLAGS -u LDFLAGS \
    LANG=C LC_ALL=C CC="$AWS_OFI_CC" CXX="$AWS_OFI_CXX" CPP="$AWS_OFI_CC -E" CFLAGS="$AWS_OFI_CFLAGS" CXXFLAGS="$AWS_OFI_CXXFLAGS" \
    ./configure --with-libfabric="$LIBFABRIC_PATH" --with-cuda="$CUDA_HOME" --disable-picky-compiler || { echo "Failed to configure AWS OFI NCCL"; exit 1; }
env LANG=C LC_ALL=C make -j "$PARALLELISM" || { echo "Failed to build AWS OFI NCCL"; exit 1; }
cd ..

# Clone and build the NCCL Tests
if [ "$SKIP_TESTS" = false ]; then
    echo "Cloning and building NCCL Tests..."
    if [ "$SKIP_CLONE" = false ] && [ ! -d "nccl-tests" ]; then
        git clone https://github.com/NVIDIA/nccl-tests.git || { echo "Failed to clone NCCL Tests repository"; exit 1; }
    fi
    if [ ! -d "nccl-tests" ]; then
        echo "Error: nccl-tests source directory $BASE_DIR/nccl-tests does not exist."
        echo "Populate it on a node with internet access, or re-run without --skip-clone from a node that can reach GitHub."
        exit 1
    fi
    cd nccl-tests
    # The nccl-tests/src Makefile needs NCCL_HOME to be set
    echo NCCL_HOME = $NCCL_HOME
    make NCCL_HOME="$NCCL_HOME" MPI=1 MPI_HOME="$MPICH_DIR" -j "$PARALLELISM" || { echo "Failed to build NCCL Tests"; exit 1; }
    cd ..
fi

write_runtime_env_files

echo "============================="
echo "Build completed successfully!"
echo "============================="
echo "NCCL_HOME: $NCCL_HOME"
echo "AWS_OFI_NCCL_HOME: $AWS_OFI_NCCL_HOME"
echo "NCCL_TESTS_HOME: $NCCL_TESTS_HOME"
echo "Runtime environment file: $BASE_DIR/setup_nccl_runtime_env.sh"
echo "all_reduce_perf wrapper: $BASE_DIR/run_all_reduce_perf.sh"
echo "To verify installation, try running the NCCL tests: "
echo "source $BASE_DIR/setup_nccl_runtime_env.sh"
echo "srun --ntasks-per-node=4 --cpus-per-task=72 --gres=gpu:4 $BASE_DIR/run_all_reduce_perf.sh -b 8 -e 128M -f 2"
