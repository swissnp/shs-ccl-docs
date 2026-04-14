#!/bin/bash
#SBATCH --job-name=build-nccl-env
#SBATCH -p gpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --gpus-per-node=1
#SBATCH --time=01:00:00
#SBATCH --output=build-nccl-env-%j.out

set -euo pipefail

REPO_DIR="${REPO_DIR:-$SLURM_SUBMIT_DIR}"
BASE_DIR="${BASE_DIR:-$REPO_DIR}"
PARALLELISM="${PARALLELISM:-$SLURM_CPUS_PER_TASK}"
LIBFABRIC_PATH="${LIBFABRIC_PATH:-/opt/cray/libfabric/1.22.0}"
NCCL_VERSION="${NCCL_VERSION:-593de54e52679b51428571c13271e2ea9f91b1b1}"
AWS_VERSION="${AWS_VERSION:-v1.19.0}"
SKIP_CLONE="${SKIP_CLONE:-true}"

cd "$REPO_DIR"

module load cudatoolkit
module load PrgEnv-cray
module swap cray-mpich cray-mpich-abi

if [ "$SKIP_CLONE" = "true" ]; then
    for required_dir in "$BASE_DIR/nccl-src" "$BASE_DIR/aws-ofi-nccl"; do
        if [ ! -d "$required_dir/.git" ]; then
            echo "Missing pre-staged git checkout: $required_dir"
            echo "Compute nodes are offline, so clone/fetch these repositories on a login node first."
            exit 1
        fi
    done

    if [ ! -d "$BASE_DIR/nccl-tests" ]; then
        echo "Missing pre-staged source directory: $BASE_DIR/nccl-tests"
        echo "Compute nodes are offline, so clone this repository on a login node first."
        exit 1
    fi
fi

./nccl/build_nccl_environment.sh \
    --base-dir "$BASE_DIR" \
    --parallelism "$PARALLELISM" \
    --libfabric-path "$LIBFABRIC_PATH" \
    --nccl-version "$NCCL_VERSION" \
    --aws-version "$AWS_VERSION" \
    $( [ "$SKIP_CLONE" = "true" ] && printf '%s' "--skip-clone" )

echo
echo "Build completed on compute node ${SLURMD_NODENAME:-unknown}."
echo "Source the runtime environment before running tests:"
echo "  source $BASE_DIR/setup_nccl_runtime_env.sh"
echo "Or use the wrapper directly:"
echo "  $BASE_DIR/run_all_reduce_perf.sh -b 8 -e 128M -f 2"
