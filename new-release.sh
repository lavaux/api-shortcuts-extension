#!/bin/bash

# Function to display help message
show_help() {
    echo "Usage: $0 [--force] [-h]"
    echo "  --force   Force the release by replacing --dry-run with --no-ci"
    echo "  -h        Show this help message and exit"
    exit 0
}

# Initialize arguments
DRY_RUN="--dry-run"
FORCE_MODE=false

# Process arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE_MODE=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Build the semantic-release command
SEMANTIC_RELEASE_CMD="npx semantic-release"
if [ "$FORCE_MODE" = true ]; then
    SEMANTIC_RELEASE_CMD="$SEMANTIC_RELEASE_CMD --no-ci"
else
    SEMANTIC_RELEASE_CMD="$SEMANTIC_RELEASE_CMD $DRY_RUN"
fi

echo "Executing: $SEMANTIC_RELEASE_CMD"
eval "$SEMANTIC_RELEASE_CMD"
