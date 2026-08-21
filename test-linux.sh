#!/bin/bash
# Test script for Linux version of ego-lite

set -e

echo "Testing ego-lite Linux version..."
echo "=================================="

# Check Node.js
echo "1. Checking Node.js..."
if command -v node >/dev/null 2>&1; then
    echo "   ✓ Node.js found: $(node --version)"
else
    echo "   ✗ Node.js not found"
    exit 1
fi

# Check npm
echo "2. Checking npm..."
if command -v npm >/dev/null 2>&1; then
    echo "   ✓ npm found: $(npm --version)"
else
    echo "   ✗ npm not found"
    exit 1
fi

# Check Chrome/Chromium
echo "3. Checking Chrome/Chromium..."
chrome_found=false
for cmd in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "   ✓ Chrome/Chromium found: $cmd"
        chrome_found=true
        break
    fi
done

if [ "$chrome_found" = false ]; then
    echo "   ⚠ Chrome/Chromium not found (optional for testing)"
fi

# Check if ego-browser wrapper exists
echo "4. Checking ego-browser wrapper..."
wrapper_path="$HOME/.local/bin/ego-browser"
if [ -x "$wrapper_path" ]; then
    echo "   ✓ ego-browser wrapper found at $wrapper_path"
else
    echo "   ⚠ ego-browser wrapper not found at $wrapper_path"
    echo "   Run install script to create it"
fi

# Test ego-browser help
echo "5. Testing ego-browser help..."
if [ -x "$wrapper_path" ]; then
    "$wrapper_path" --help >/dev/null 2>&1
    echo "   ✓ ego-browser help works"
else
    echo "   ⚠ Skipping ego-browser help test (wrapper not found)"
fi

# Test ego-browser doctor
echo "6. Testing ego-browser doctor..."
if [ -x "$wrapper_path" ]; then
    "$wrapper_path" --doctor
else
    echo "   ⚠ Skipping ego-browser doctor test (wrapper not found)"
fi

echo ""
echo "Test completed!"
echo ""
echo "To fully test ego-browser:"
echo "1. Start Chrome with remote debugging: google-chrome --remote-debugging-port=9222"
echo "2. Run a test script: ego-browser nodejs <<'EOF' console.log('Hello from ego-browser!') EOF"
