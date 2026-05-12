#!/bin/bash

# Simple Runpod endpoint test script
# Loads .env, submits a test job, and monitors its status

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date -u +"%Y-%m-%dT%H:%M:%SZ")]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Load environment
if [ ! -f .env ]; then
    error ".env file not found in current directory"
    exit 1
fi

log "Loading environment from .env..."
set -a
source .env
set +a

# Validate required variables
if [ -z "$RUNPOD_ENDPOINT_ID" ] || [ -z "$RUNPOD_API_KEY" ]; then
    error "RUNPOD_ENDPOINT_ID or RUNPOD_API_KEY not set in .env"
    exit 1
fi

log "Endpoint ID: $RUNPOD_ENDPOINT_ID"
log "API Key: ${RUNPOD_API_KEY:0:10}...***"

# Test parameters
MAX_WAIT_SECONDS=600
POLL_INTERVAL=5
TEST_PROMPT="What is your name? Reply in one word."
RUN_URL="https://api.runpod.ai/v2/$RUNPOD_ENDPOINT_ID/runsync"

log "Submitting test job..."
log "Prompt: $TEST_PROMPT"
log "URL: $RUN_URL"

# Submit test job
RESPONSE=$(curl -sS -X POST "$RUN_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" \
    -d "{\"input\":{\"prompt\":\"$TEST_PROMPT\",\"stream\":false}}")

log "API Response: $RESPONSE"

# Check for error responses
if echo "$RESPONSE" | grep -q "Not Found"; then
    error "Endpoint not found (404)"
    error "Possible causes:"
    error "  1. Endpoint ID is invalid or outdated"
    error "  2. Endpoint was deleted/recreated with a new ID"
    error "  3. Endpoint is in a different region"
    error ""
    error "Check your Runpod console:"
    error "  https://console.runpod.io/serverless"
    error ""
    error "Update .env with the correct endpoint ID and retry."
    exit 1
fi

if echo "$RESPONSE" | grep -q "error"; then
    error "API Error: $RESPONSE"
    exit 1
fi

# Extract job ID
JOB_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
JOB_STATUS=$(echo "$RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

if [ -z "$JOB_ID" ]; then
    error "Failed to get job ID from response"
    error "Response was: $RESPONSE"
    exit 1
fi

log "Job ID: $JOB_ID"
log "Initial Status: $JOB_STATUS"

# Poll for result
STATUS_URL="https://api.runpod.ai/v2/$RUNPOD_ENDPOINT_ID/status/$JOB_ID"
ELAPSED=0
POLL_COUNT=0

log "Polling for result (max ${MAX_WAIT_SECONDS}s, interval ${POLL_INTERVAL}s)..."

while [ $ELAPSED -lt $MAX_WAIT_SECONDS ]; do
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
    POLL_COUNT=$((POLL_COUNT + 1))

    STATUS_RESPONSE=$(curl -sS -H "Authorization: Bearer $RUNPOD_API_KEY" "$STATUS_URL")
    
    CURRENT_STATUS=$(echo "$STATUS_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    
    log "Poll #$POLL_COUNT (${ELAPSED}s): Status = $CURRENT_STATUS"

    if [ "$CURRENT_STATUS" = "COMPLETED" ]; then
        log "Job completed!"
        success "Endpoint is working!"
        
        # Extract and display output
        echo ""
        log "Full response:"
        echo "$STATUS_RESPONSE" | jq '.' 2>/dev/null || echo "$STATUS_RESPONSE"
        
        exit 0
    elif [ "$CURRENT_STATUS" = "FAILED" ]; then
        error "Job failed"
        log "Full response:"
        echo "$STATUS_RESPONSE" | jq '.' 2>/dev/null || echo "$STATUS_RESPONSE"
        exit 1
    fi
done

error "Test timed out after ${MAX_WAIT_SECONDS}s"
warn "Job remains in status: $CURRENT_STATUS"
warn "Check Runpod console for worker logs"
log "You can check status manually at:"
log "https://api.runpod.ai/v2/$RUNPOD_ENDPOINT_ID/status/$JOB_ID"
exit 1
