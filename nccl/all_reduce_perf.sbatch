#!/bin/bash
#SBATCH --job-name=nccl-all-reduce
#SBATCH -p gpu
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=72
#SBATCH --gpus-per-node=4
#SBATCH --time=00:15:00
#SBATCH --output=nccl-all-reduce-%j.out

set -euo pipefail

REPO_DIR="${REPO_DIR:-$SLURM_SUBMIT_DIR}"
BASE_DIR="${BASE_DIR:-$REPO_DIR}"
RUNTIME_ENV_FILE="${RUNTIME_ENV_FILE:-$BASE_DIR/setup_nccl_runtime_env.sh}"
RUN_WRAPPER="${RUN_WRAPPER:-$BASE_DIR/run_all_reduce_perf.sh}"
TASKS_PER_NODE="${TASKS_PER_NODE:-4}"
CPUS_PER_TASK="${CPUS_PER_TASK:-72}"
MESSAGE_SIZE_BEGIN="${MESSAGE_SIZE_BEGIN:-8}"
MESSAGE_SIZE_END="${MESSAGE_SIZE_END:-4G}"
MESSAGE_SIZE_FACTOR="${MESSAGE_SIZE_FACTOR:-2}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
SOURCE_CCL_ENV="${SOURCE_CCL_ENV:-auto}"

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

if [ "$SOURCE_CCL_ENV" = "true" ] || { [ "$SOURCE_CCL_ENV" = "auto" ] && [ "${SLURM_NNODES:-1}" -gt 1 ]; }; then
    source "$REPO_DIR/ccl_env.sh"
fi

srun \
    --ntasks-per-node="$TASKS_PER_NODE" \
    --cpus-per-task="$CPUS_PER_TASK" \
    --network=disable_rdzv_get \
    "$RUN_WRAPPER" \
    -b "$MESSAGE_SIZE_BEGIN" \
    -e "$MESSAGE_SIZE_END" \
    -f "$MESSAGE_SIZE_FACTOR" \
    $EXTRA_ARGS
