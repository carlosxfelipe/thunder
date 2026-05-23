#!/usr/bin/env bash
# Runs the Thunder test suite via xcodebuild.
# Usage: ./scripts/run_tests.sh

echo "⚡️ Running Thunder test suite..."
xcodebuild test -project thunar.xcodeproj -scheme thunar -destination 'platform=macOS' | xcpretty || xcodebuild test -project thunar.xcodeproj -scheme thunar -destination 'platform=macOS'
