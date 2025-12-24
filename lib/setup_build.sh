#!/bin/bash
# Setup script for VST3Host build
# Downloads the VST3 SDK if not present

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VST3_SDK_DIR="$SCRIPT_DIR/vst3sdk"
VST3_SDK_URL="https://github.com/steinbergmedia/vst3sdk.git"

if [ -d "$VST3_SDK_DIR" ]; then
    echo "VST3 SDK already present at $VST3_SDK_DIR"
else
    echo "Downloading VST3 SDK..."
    git clone --depth 1 "$VST3_SDK_URL" "$VST3_SDK_DIR"
    echo "VST3 SDK downloaded successfully"
fi

echo "Build setup complete. Run 'make' to build the library."
