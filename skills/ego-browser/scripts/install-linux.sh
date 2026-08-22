#!/bin/bash
# Linux install script for ego-browser
# This script sets up ego-browser to work with Chrome/Chromium on Linux
#
# Requires bash (not POSIX sh) because of the array usage in find_chrome().

set -eu

APP_NAME="ego lite"
EGO_BROWSER_HELPER_NAME="ego-browser"

log() {
    printf '%s\n' "$*" >&2
}

die() {
    log "error: $*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

# Detect Chrome or Chromium
find_chrome() {
    local chrome_paths=(
        "/usr/bin/google-chrome"
        "/usr/bin/google-chrome-stable"
        "/usr/bin/chromium"
        "/usr/bin/chromium-browser"
        "/snap/bin/chromium"
        "/usr/lib/chromium/chromium"
        "/opt/google/chrome/chrome"
    )

    for path in "${chrome_paths[@]}"; do
        if [ -x "$path" ]; then
            printf '%s\n' "$path"
            return 0
        fi
    done

    # Try to find via command -v
    for cmd in google-chrome google-chrome-stable chromium chromium-browser; do
        if command -v "$cmd" >/dev/null 2>&1; then
            command -v "$cmd"
            return 0
        fi
    done

    return 1
}

# Create wrapper script for ego-browser
create_ego_browser_wrapper() {
    local chrome_path="$1"
    local wrapper_dir="$HOME/.local/bin"
    local wrapper_path="$wrapper_dir/$EGO_BROWSER_HELPER_NAME"

    mkdir -p "$wrapper_dir"

    cat > "$wrapper_path" << 'WRAPPER_EOF'
#!/bin/sh
# ego-browser wrapper for Linux
# This wrapper connects to a Chrome/Chromium instance running with remote debugging

CHROME_PATH="${EGO_BROWSER_CHROME_PATH:-/usr/bin/google-chrome}"
DEBUGGING_PORT="${EGO_BROWSER_DEBUGGING_PORT:-9222}"
DEBUGGING_URL="http://127.0.0.1:$DEBUGGING_PORT"

# Detect Chrome or Chromium (POSIX sh, mirrors install-linux.sh's find_chrome;
# duplicated here because this wrapper runs as its own script and does not
# inherit functions from the installer)
find_chrome() {
    for path in /usr/bin/google-chrome /usr/bin/google-chrome-stable \
        /usr/bin/chromium /usr/bin/chromium-browser \
        /snap/bin/chromium /usr/lib/chromium/chromium /opt/google/chrome/chrome; do
        if [ -x "$path" ]; then
            printf '%s\n' "$path"
            return 0
        fi
    done

    for cmd in google-chrome google-chrome-stable chromium chromium-browser; do
        if command -v "$cmd" >/dev/null 2>&1; then
            command -v "$cmd"
            return 0
        fi
    done

    return 1
}

# Check if Chrome is already running with remote debugging
check_chrome_running() {
    curl -s "$DEBUGGING_URL/json/version" >/dev/null 2>&1
}

# Start Chrome with remote debugging if not running
start_chrome_with_debugging() {
    local user_data_dir="$HOME/.ego-lite-chrome-profile"
    mkdir -p "$user_data_dir"
    
    "$CHROME_PATH" \
        --remote-debugging-port="$DEBUGGING_PORT" \
        --user-data-dir="$user_data_dir" \
        --no-first-run \
        --no-default-browser-check \
        "$@" &
    
    # Wait for Chrome to start
    local max_wait=10
    local wait_count=0
    while ! check_chrome_running && [ $wait_count -lt $max_wait ]; do
        sleep 1
        wait_count=$((wait_count + 1))
    done
    
    if ! check_chrome_running; then
        echo "Failed to start Chrome with remote debugging" >&2
        exit 1
    fi
}

# Main execution
case "$1" in
    nodejs)
        # If no arguments after 'nodejs', read from stdin
        shift
        if [ $# -eq 0 ]; then
            # Start Chrome if not running
            if ! check_chrome_running; then
                start_chrome_with_debugging
            fi
            
            # Execute the Node.js script with browser connection
            # Uses Node's built-in global WebSocket (stable since Node 22) instead of the
            # 'ws' package, since this wrapper is copied to ~/.local/bin and runs detached
            # from the repo's node_modules.
            exec node -e "
async function connectToBrowser() {
    const response = await fetch('$DEBUGGING_URL/json/version');
    const data = await response.json();
    const wsUrl = data.webSocketDebuggerUrl;

    const ws = new WebSocket(wsUrl);

    ws.onopen = () => {
        // Create globalThis.ego object
        globalThis.ego = {
            sendCDPMessage: (message) => {
                ws.send(message);
            },
            onCDPMessage: null,
            onSendCDPMessageError: null,
            listTabs: async () => {
                const resp = await fetch('$DEBUGGING_URL/json');
                return { tabs: await resp.json() };
            },
            listTaskSpaces: async () => {
                return { taskSpaces: [] };
            },
            useTaskSpace: async () => {},
            createTaskSpace: async () => {
                return { taskId: 'default', id: 1, name: 'default' };
            },
            claimTaskSpace: async () => {},
            closeTaskSpace: async () => {},
            handOffTaskSpace: async () => {},
            takeOverTaskSpace: async () => {},
            completeTaskSpace: async () => {},
            snapshot: async () => {
                return { refs: [] };
            }
        };
        
        ws.onmessage = (event) => {
            if (globalThis.ego.onCDPMessage) {
                globalThis.ego.onCDPMessage(String(event.data));
            }
        };

        // Execute the script from stdin
        let code = '';
        process.stdin.setEncoding('utf8');
        process.stdin.on('data', (chunk) => code += chunk);
        process.stdin.on('end', async () => {
            try {
                const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
                const fn = new AsyncFunction(code);
                await fn();
            } catch (error) {
                console.error(error);
                process.exit(1);
            }
            ws.close();
            process.exit(0);
        });
    };

    ws.onerror = (event) => {
        console.error('WebSocket error:', event.message || event);
        process.exit(1);
    };
}

connectToBrowser().catch(error => {
    console.error(error);
    process.exit(1);
});
"
        fi
        ;;
    --doctor)
        echo "ego-browser doctor (Linux)"
        echo "=========================="
        
        # Check Chrome
        if chrome_path=$(find_chrome); then
            echo "✓ Chrome/Chromium found: $chrome_path"
        else
            echo "✗ Chrome/Chromium not found"
            echo "  Please install Chrome or Chromium"
        fi
        
        # Check Node.js
        if command -v node >/dev/null 2>&1; then
            echo "✓ Node.js found: $(node --version)"
        else
            echo "✗ Node.js not found"
            echo "  Please install Node.js 22 or later"
        fi
        
        # Check if Chrome is running with debugging
        if check_chrome_running; then
            echo "✓ Chrome remote debugging available at $DEBUGGING_URL"
        else
            echo "⚠ Chrome remote debugging not available"
            echo "  Start Chrome with: google-chrome --remote-debugging-port=$DEBUGGING_PORT"
        fi
        
        exit 0
        ;;
    --reload)
        echo "Browser connection reset on next call"
        exit 0
        ;;
    -h|--help)
        echo "ego-browser (Linux version)"
        echo ""
        echo "Usage:"
        echo "  ego-browser nodejs <<'EOF'"
        echo "    // Your JavaScript code here"
        echo "  EOF"
        echo ""
        echo "Commands:"
        echo "  ego-browser --doctor    Check browser and connection state"
        echo "  ego-browser --reload    Reset browser connection on next call"
        echo "  ego-browser -h|--help   Show this help"
        echo ""
        echo "Environment variables:"
        echo "  EGO_BROWSER_CHROME_PATH       Path to Chrome/Chromium (default: auto-detect)"
        echo "  EGO_BROWSER_DEBUGGING_PORT    Chrome debugging port (default: 9222)"
        exit 0
        ;;
    *)
        echo "Usage: ego-browser nodejs <<'EOF'" >&2
        echo "  // Your JavaScript code here" >&2
        echo "EOF" >&2
        exit 2
        ;;
esac
WRAPPER_EOF

    chmod +x "$wrapper_path"
    log "Created ego-browser wrapper at $wrapper_path"
    log "Make sure $wrapper_dir is in your PATH"
}

# Main installation
main() {
    [ "$(uname -s)" = "Linux" ] || die "this script only supports Linux"
    
    log "Setting up ego-browser for Linux..."
    
    # Check requirements
    require_command node
    require_command npm
    
    # Check Node.js version
    node_version=$(node --version | sed 's/v//' | cut -d. -f1)
    if [ "$node_version" -lt 22 ]; then
        die "Node.js 22 or later is required (found $(node --version))"
    fi
    
    # Find Chrome
    if chrome_path=$(find_chrome); then
        log "Found Chrome/Chromium: $chrome_path"
    else
        log "Warning: Chrome/Chromium not found"
        log "Please install Chrome or Chromium before using ego-browser"
        log ""
        log "You can install Chrome with:"
        log "  # Debian/Ubuntu:"
        log "  wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -"
        log "  sudo sh -c 'echo \"deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main\" >> /etc/apt/sources.list.d/google.list'"
        log "  sudo apt update"
        log "  sudo apt install google-chrome-stable"
        log ""
        log "  # Fedora/RHEL:"
        log "  sudo dnf install google-chrome-stable"
        log ""
        log "  # Arch Linux:"
        log "  sudo pacman -S chromium"
    fi
    
    # Create wrapper script
    create_ego_browser_wrapper "${chrome_path:-/usr/bin/google-chrome}"
    
    # Install Node.js dependencies
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    package_dir="$(dirname "$script_dir")"
    
    if [ -f "$package_dir/package.json" ]; then
        log "Installing Node.js dependencies..."
        cd "$package_dir"
        npm ci 2>/dev/null || npm install
    fi
    
    log ""
    log "Installation complete!"
    log ""
    log "To use ego-browser:"
    log "1. Make sure Chrome/Chromium is running with remote debugging:"
    log "   google-chrome --remote-debugging-port=9222"
    log ""
    log "2. Use ego-browser:"
    log "   ego-browser nodejs <<'EOF'"
    log "     console.log('Hello from ego-browser!')"
    log "   EOF"
    log ""
    log "For more information, run: ego-browser --help"
}

main "$@"
