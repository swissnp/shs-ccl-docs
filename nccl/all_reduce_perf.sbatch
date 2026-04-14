#!/bin/bash
#SBATCH --job-name=nccl-all-reduce
#SBATCH -p gpu
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=16
#SBATCH --gpus-per-node=4
#SBATCH --time=00:15:00
#SBATCH --output=nccl-all-reduce-%j.out

set -euo pipefail

REPO_DIR="${REPO_DIR:-$SLURM_SUBMIT_DIR}"
BASE_DIR="${BASE_DIR:-$REPO_DIR}"
RUNTIME_ENV_FILE="${RUNTIME_ENV_FILE:-$BASE_DIR/setup_nccl_runtime_env.sh}"
RUN_WRAPPER="${RUN_WRAPPER:-$BASE_DIR/run_all_reduce_perf.sh}"
TASKS_PER_NODE="${TASKS_PER_NODE:-4}"
CPUS_PER_TASK="${CPUS_PER_TASK:-16}"
MESSAGE_SIZE_BEGIN="${MESSAGE_SIZE_BEGIN:-8}"
MESSAGE_SIZE_END="${MESSAGE_SIZE_END:-4G}"
MESSAGE_SIZE_FACTOR="${MESSAGE_SIZE_FACTOR:-2}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
SOURCE_CCL_ENV="${SOURCE_CCL_ENV:-auto}"
NCCL_DEBUG_LEVEL="${NCCL_DEBUG_LEVEL:-WARN}"
NCCL_CUMEM_ENABLE_VALUE="${NCCL_CUMEM_ENABLE_VALUE:-0}"
NCCL_CUMEM_HOST_ENABLE_VALUE="${NCCL_CUMEM_HOST_ENABLE_VALUE:-0}"

cd "$REPO_DIR"

module load cudatoolkit
module load PrgEnv-cray
module swap cray-mpich cray-mpich-abi

if [ ! -f "$RUNTIME_ENV_FILE" ]; then
    echo "Missing runtime environment file: $RUNTIME_ENV_FILE"
    echo "Run nccl/build_nccl_environment.sh or nccl/build_nccl_environment.sbatch first."
    exit 1
fi

if [ ! -x "$RUN_WRAPPER" ]; then
    echo "Missing all_reduce_perf wrapper: $RUN_WRAPPER"
    echo "Run nccl/build_nccl_environment.sh or nccl/build_nccl_environment.sbatch first."
    exit 1
fi

source "$RUNTIME_ENV_FILE"
export NCCL_DEBUG="$NCCL_DEBUG_LEVEL"
export NCCL_CUMEM_ENABLE="$NCCL_CUMEM_ENABLE_VALUE"
export NCCL_CUMEM_HOST_ENABLE="$NCCL_CUMEM_HOST_ENABLE_VALUE"

if [ "$SOURCE_CCL_ENV" = "true" ] || { [ "$SOURCE_CCL_ENV" = "auto" ] && [ "${SLURM_NNODES:-1}" -gt 1 ]; }; then
    source "$REPO_DIR/ccl_env.sh"
elif [ "${SLURM_NNODES:-1}" -eq 1 ]; then
    # Single-node runs should not force the Libfabric transport.
    unset NCCL_NET
fi

echo "Running all_reduce_perf with $TASKS_PER_NODE tasks per node and $CPUS_PER_TASK CPUs per task."
echo "Override with: sbatch --export=ALL,TASKS_PER_NODE=<gpus>,CPUS_PER_TASK=<cpus-per-rank> nccl/all_reduce_perf.sbatch"
echo "NCCL_DEBUG=$NCCL_DEBUG NCCL_CUMEM_ENABLE=$NCCL_CUMEM_ENABLE NCCL_CUMEM_HOST_ENABLE=$NCCL_CUMEM_HOST_ENABLE"

srun \
    --ntasks-per-node="$TASKS_PER_NODE" \
    --cpus-per-task="$CPUS_PER_TASK" \
    --network=disable_rdzv_get \
    "$RUN_WRAPPER" \
    -b "$MESSAGE_SIZE_BEGIN" \
    -e "$MESSAGE_SIZE_END" \
    -f "$MESSAGE_SIZE_FACTOR" \
    $EXTRA_ARGS
