#!/bin/bash

# fail on error:
set -e -o pipefail

# This script starts the llama-server with the command line arguments
# specified in the environment variable LLAMA_SERVER_CMD_ARGS, ensuring
# that the server listens on port 3098. It also starts the handler.py
# script after the server is up and running.

log() {
    echo "start.sh: $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"
}

print_llama_log_tail() {
    if [ -f llama.server.log ]; then
        log "Last llama.server.log lines:"
        tail -n 50 llama.server.log
    else
        log "llama.server.log does not exist yet"
    fi
}

cleanup() {
    log "Cleaning up..."
    pkill -P $$ # kill all child processes of the current script
    exit 0
}

CACHED_LLAMA_ARGS=""

find_cached_path() {
    local model_path
    local mmproj_path
    local debug_output

    log "Resolving cached model path for $LLAMA_CACHED_MODEL / $LLAMA_CACHED_GGUF_PATH"

    model_path=$(python ./find_cached.py "$LLAMA_CACHED_MODEL" "$LLAMA_CACHED_GGUF_PATH")

    if [ -z "$model_path" ] || [ "$model_path" = "None" ]; then
        log "Error: Cached model path not found for $LLAMA_CACHED_MODEL / $LLAMA_CACHED_GGUF_PATH"
        log "Collecting cache lookup diagnostics..."
        debug_output=$(python ./find_cached.py "$LLAMA_CACHED_MODEL" "$LLAMA_CACHED_GGUF_PATH" --debug 2>&1 >/dev/null || true)
        echo "$debug_output" | sed 's/^/start.sh: /'
        exit 1
    fi

    log "Resolved model path: $model_path"

    CACHED_LLAMA_ARGS="-m $model_path"

    # Optional: explicitly resolve multimodal projector path from cache.
    if [ -n "$LLAMA_CACHED_MMPROJ_PATH" ]; then
        log "Resolving cached mmproj path for $LLAMA_CACHED_MODEL / $LLAMA_CACHED_MMPROJ_PATH"
        mmproj_path=$(python ./find_cached.py "$LLAMA_CACHED_MODEL" "$LLAMA_CACHED_MMPROJ_PATH")

        if [ -z "$mmproj_path" ] || [ "$mmproj_path" = "None" ]; then
            log "Error: Cached mmproj path not found for $LLAMA_CACHED_MODEL / $LLAMA_CACHED_MMPROJ_PATH"
            log "Collecting mmproj lookup diagnostics..."
            debug_output=$(python ./find_cached.py "$LLAMA_CACHED_MODEL" "$LLAMA_CACHED_MMPROJ_PATH" --debug 2>&1 >/dev/null || true)
            echo "$debug_output" | sed 's/^/start.sh: /'
            exit 1
        fi

        log "Resolved mmproj path: $mmproj_path"

        CACHED_LLAMA_ARGS="$CACHED_LLAMA_ARGS -mm $mmproj_path"
    fi
}

# check if $LLAMA_CACHED_MODEL is set and not empty
if [ -n "$LLAMA_CACHED_MODEL" ]; then
    log "Caching is enabled. Finding cached model path..."
    find_cached_path

    log "Using cached model arguments: $CACHED_LLAMA_ARGS"
else
    log "WARNING: Caching is disabled. Please visit the inference-worker README and docs to learn more."
fi

# check if $LLAMA_SERVER_CMD_ARGS is set
if [ -z "$LLAMA_SERVER_CMD_ARGS" ]; then
    log "Warning: LLAMA_SERVER_CMD_ARGS is not set. Defaulting to -hf unsloth/gemma-3-270m-it-GGUF:IQ2_XXS --ctx-size 512 -ngl 999"
    LLAMA_SERVER_CMD_ARGS="-hf unsloth/gemma-3-270m-it-GGUF:IQ2_XXS --ctx-size 512 -ngl 999"
fi

# check if the substring --port is in LLAMA_SERVER_CMD_ARGS and if yes, raise an error:
if [[ "$LLAMA_SERVER_CMD_ARGS" == *"--port"* ]]; then
    log "Error: You must not define --port in LLAMA_SERVER_CMD_ARGS, as port 3098 is required."
    exit 1
fi

# trap exit signals and call the cleanup function
trap cleanup SIGINT SIGTERM

# kill any existing llama-server processes
log "Starting worker bootstrap in $(pwd)"
log "Python: $(command -v python || echo missing)"
log "LLAMA_CACHED_MODEL=${LLAMA_CACHED_MODEL:-<unset>}"
log "LLAMA_CACHED_GGUF_PATH=${LLAMA_CACHED_GGUF_PATH:-<unset>}"
log "LLAMA_CACHED_MMPROJ_PATH=${LLAMA_CACHED_MMPROJ_PATH:-<unset>}"
log "MAX_CONCURRENCY=${MAX_CONCURRENCY:-<unset>}"
log "LLAMA_SERVER_CMD_ARGS=$LLAMA_SERVER_CMD_ARGS"
log "Stopping existing llama-server instances (if any)..."
{
    pkill llama-server 2>/dev/null
} || {
    log "No llama-server running"
}

# we have a string with all the command line arguments in the env var LLAMA_SERVER_CMD_ARGS;
# it contains a.e. "-hf modelname --ctx-size 4096 -ngl 999".

log "Running /app/llama-server $CACHED_LLAMA_ARGS $LLAMA_SERVER_CMD_ARGS --port 3098"

touch llama.server.log

# We need to pass these arguments to llama-server verbatim.
LD_LIBRARY_PATH=/app /app/llama-server $CACHED_LLAMA_ARGS $LLAMA_SERVER_CMD_ARGS --port 3098 2>&1 | tee llama.server.log &

LLAMA_SERVER_PID=$! # store the process ID (PID) of the background command
log "llama-server background PID: $LLAMA_SERVER_PID"

tries_so_far=0

check_server_is_running() {
    log "Checking if llama-server is done initializing (attempt $tries_so_far)..."

    tries_so_far=$((tries_so_far + 1))

    if cat llama.server.log | grep -q "listening"; then
        return 0 # success
    fi

    if [ $tries_so_far -ge 120 ]; then
        log "Error: llama-server did not start within 60 seconds."
        print_llama_log_tail
        exit 1
    fi

    # check if the process is still running
    if ! kill -0 $LLAMA_SERVER_PID 2>/dev/null; then
        log "Error: llama-server process has exited unexpectedly."
        print_llama_log_tail
        exit 1
    fi

    return 1 # failure
}

log "Waiting for llama-server to start..."

# wait for the server to start
while ! check_server_is_running; do
    # we don't want to lose too much time, so we check very frequently
    sleep 0.5
done

log "llama-server is up and running, delegating to the handler script."

log "Executing python -u handler.py $1"
python -u handler.py $1
