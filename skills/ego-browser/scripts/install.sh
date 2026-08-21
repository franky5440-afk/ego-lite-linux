#!/bin/sh
#v1.6 2026.08.22 - Added Linux support

set -eu

# Default package URL and installation paths
DMG_URL_ARM64="https://cdn.ego.app/setup/macos/arm64/egolite-fHoqgZ74bOEM.dmg"
DMG_URL_X64="https://cdn.ego.app/setup/macos/x64/egolite-fHoqgZ74bOEM.dmg"
APP_NAME="ego lite"
APP_BUNDLE_NAME="$APP_NAME.app"
APP_PATH="/Applications/$APP_BUNDLE_NAME"
USER_APP_PATH="$HOME/Applications/$APP_BUNDLE_NAME"
EGO_BROWSER_HELPER_NAME="ego-browser"

# Temporary directories created when mounting the DMG; cleaned up on exit.
TEMP_DIR=""
MOUNT_DIR=""
DMG_ATTACHED=""

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

select_dmg_url() {
    if [ "$(uname -m)" = "arm64" ]; then
        printf '%s\n' "$DMG_URL_ARM64"
    else
        printf '%s\n' "$DMG_URL_X64"
    fi
}

run_with_sudo_if_needed() {
    # Try without elevated privileges first; fall back to sudo to avoid unnecessary prompts.
    if "$@"; then
        return 0
    fi

    if [ "$(id -u)" -eq 0 ]; then
        return 1
    fi

    require_command sudo
    sudo "$@"
}

cleanup() {
    # Detach the DMG and remove the temp directory on success, failure, or Ctrl+C.
    if [ "$DMG_ATTACHED" = "1" ]; then
        if ! hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1; then
            log "warning: failed to detach $MOUNT_DIR"
        fi
        DMG_ATTACHED=""
    fi

    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR" >/dev/null 2>&1 ||
            log "warning: failed to remove temporary directory: $TEMP_DIR"
    fi
}

strip_quarantine_attributes() {
    app_path="$1"
    run_with_sudo_if_needed xattr -dr com.apple.quarantine "$app_path" \
        >/dev/null 2>&1 || true
}

trap cleanup EXIT HUP INT TERM

find_ego_browser_in_app() {
    app_path="$1"

    [ -d "$app_path/Contents" ] || return 1

    # A Chromium app bundle may contain multiple versions; prefer the one under Current.
    for candidate in "$app_path"/Contents/Frameworks/*.framework/Versions/Current/Helpers/"$EGO_BROWSER_HELPER_NAME"; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    # ego-browser may live in various locations inside the bundle; search under Contents.
    browser_path=$(
        find "$app_path/Contents" -type f -name "$EGO_BROWSER_HELPER_NAME" 2>/dev/null |
            while IFS= read -r candidate; do
                if [ -x "$candidate" ]; then
                    printf '%s\n' "$candidate"
                    break
                fi
            done
    )

    if [ -n "$browser_path" ]; then
        printf '%s\n' "$browser_path"
        return 0
    fi

    return 1
}

is_ego_lite_app() {
    app_path="$1"

    # The directory exists and contains a working ego-browser — ego lite is considered installed.
    [ -d "$app_path" ] || return 1
    find_ego_browser_in_app "$app_path" >/dev/null
}

find_ego_lite_app() {
    for app_path in "$APP_PATH" "$USER_APP_PATH"; do
        if is_ego_lite_app "$app_path"; then
            printf '%s\n' "$app_path"
            return 0
        fi
    done

    for apps_dir in "$(dirname "$APP_PATH")" "$(dirname "$USER_APP_PATH")"; do
        [ -d "$apps_dir" ] || continue

        app_path=$(
            find "$apps_dir" -maxdepth 1 -type d -iname "$APP_BUNDLE_NAME" 2>/dev/null |
                while IFS= read -r candidate; do
                    if is_ego_lite_app "$candidate"; then
                        printf '%s\n' "$candidate"
                        break
                    fi
                done
        )
        if [ -n "$app_path" ]; then
            printf '%s\n' "$app_path"
            return 0
        fi
    done

    return 1
}

install_ego_lite_macos() {
    require_command curl
    require_command hdiutil

    # Download and mount the DMG in an isolated temp directory to avoid polluting the CWD.
    temp_base_dir=${TMPDIR:-/tmp}
    temp_base_dir=${temp_base_dir%/}
    TEMP_DIR=$(mktemp -d "$temp_base_dir/ego-lite-install.XXXXXX")
    MOUNT_DIR="$TEMP_DIR/mount"
    dmg_path="$TEMP_DIR/egolite.dmg"
    dmg_url=$(select_dmg_url)
    mkdir -p "$MOUNT_DIR"

    log "$APP_NAME is not installed. Downloading $dmg_url ..."
    curl -fL --retry 3 --output "$dmg_path" "$dmg_url" ||
        die "failed to download $APP_NAME from $dmg_url"

    log "Mounting installer ..."
    hdiutil attach "$dmg_path" -nobrowse -readonly -mountpoint "$MOUNT_DIR" \
        >/dev/null
    DMG_ATTACHED="1"

    # Handle DMGs that contain the app bundle directly.
    app_in_dmg=$(
        find "$MOUNT_DIR" -maxdepth 2 \
            -type d -iname "$APP_BUNDLE_NAME" |
            head -n 1
    )

    if [ -n "$app_in_dmg" ]; then
        staged_app="$TEMP_DIR/$APP_BUNDLE_NAME"

        log "Installing $APP_NAME to $APP_PATH ..."
        ditto "$app_in_dmg" "$staged_app" ||
            die "failed to stage $APP_NAME from installer"
        find_ego_browser_in_app "$staged_app" >/dev/null ||
            die "installed $APP_NAME does not contain $EGO_BROWSER_HELPER_NAME"

        # Strip quarantine attributes to prevent Gatekeeper from blocking the first launch.
        log "Removing quarantine attributes from $APP_NAME ..."
        xattr -dr com.apple.quarantine "$staged_app" \
            >/dev/null 2>&1 || true

        if [ -d "$APP_PATH" ]; then
            run_with_sudo_if_needed rm -rf "$APP_PATH" ||
                die "failed to replace existing $APP_PATH"
        fi
        run_with_sudo_if_needed mv "$staged_app" "$APP_PATH" ||
            die "failed to move $APP_NAME to $APP_PATH"
        return 0
    fi

    # Fall back to pkg installer if the DMG contains a .pkg instead of an app bundle.
    pkg_in_dmg=$(
        find "$MOUNT_DIR" -maxdepth 2 -type f -name "*.pkg" |
            head -n 1
    )

    if [ -n "$pkg_in_dmg" ]; then
        log "Installing $APP_NAME package ..."
        run_with_sudo_if_needed installer -pkg "$pkg_in_dmg" -target / ||
            die "failed to install $APP_NAME package"
        return 0
    fi

    die "cannot find $APP_NAME app or pkg in mounted DMG"
}

# Linux installation functions
find_chrome_linux() {
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

install_ego_browser_linux() {
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
    if chrome_path=$(find_chrome_linux); then
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
        return 1
    fi
    
    # Create wrapper script
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
            exec node -e "
const http = require('http');
const WebSocket = require('ws');

async function connectToBrowser() {
    const response = await fetch('$DEBUGGING_URL/json/version');
    const data = await response.json();
    const wsUrl = data.webSocketDebuggerUrl;
    
    const ws = new WebSocket(wsUrl);
    
    ws.on('open', () => {
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
        
        ws.on('message', (message) => {
            if (globalThis.ego.onCDPMessage) {
                globalThis.ego.onCDPMessage(message.toString());
            }
        });
        
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
    });
    
    ws.on('error', (error) => {
        console.error('WebSocket error:', error);
        process.exit(1);
    });
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
        if chrome_path=$(find_chrome_linux); then
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
    
    # Install Node.js dependencies if package.json exists
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

# Main installation
main() {
    case "$(uname -s)" in
        Darwin)
            # macOS installation
            installed_app_path=$(find_ego_lite_app || true)
            if [ -z "$installed_app_path" ]; then
                install_ego_lite_macos
                installed_app_path=$(find_ego_lite_app || true)
                [ -n "$installed_app_path" ] ||
                    die "$APP_NAME install completed, but app was not found"
            fi

            strip_quarantine_attributes "$installed_app_path"
            cleanup

            log "Launching $APP_NAME ..."
            exec open "$installed_app_path"
            ;;
        Linux)
            # Linux installation
            install_ego_browser_linux
            ;;
        *)
            die "unsupported platform: $(uname -s)"
            ;;
    esac
}

main
