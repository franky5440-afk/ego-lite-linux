# ego-lite Linux Support Implementation

## Overview

This document provides a comprehensive summary of the changes made to make ego-lite work on Linux systems.

## Problem Statement

The original ego-lite project only supports macOS. The goal was to create a Linux-compatible version that:
1. Works with standard Chrome/Chromium browsers
2. Provides the same API as the macOS version
3. Is easy to install and use on Linux

## Solution

The Linux version works by:
1. **Connecting to Chrome/Chromium**: Instead of using the custom ego lite browser, it connects to a standard Chrome or Chromium instance running with remote debugging enabled.

2. **Chrome DevTools Protocol (CDP)**: Uses the same CDP protocol as the macOS version to control the browser.

3. **Wrapper Script**: A shell script at `~/.local/bin/ego-browser` handles:
   - Starting Chrome with remote debugging if not already running
   - Connecting to Chrome via WebSocket
   - Providing the same API as the macOS version

## Files Modified

### 1. `skills/ego-browser/scripts/install.sh`
- Added Linux support to the main install script
- The script now detects the operating system and runs appropriate installation steps
- On macOS: Uses the original DMG installation process
- On Linux: Creates a wrapper script that connects to Chrome/Chromium with remote debugging

### 2. `skills/ego-browser/scripts/install-linux.sh` (New)
- Standalone script for Linux installation
- Detects Chrome/Chromium installation
- Creates a wrapper script at `~/.local/bin/ego-browser`
- Provides doctor command to check browser and Node.js status

### 3. `LINUX_README.md` (New)
- Comprehensive guide for using ego-lite on Linux
- Installation instructions for Chrome/Chromium
- Usage examples
- Troubleshooting guide
- Comparison with macOS version

### 4. `README.md`
- Added mention of Linux support
- Added reference to Linux README
- Updated download section to mention Linux alternative

### 5. `LINUX_CHANGES.md` (New)
- Summary of all changes made
- How the Linux version works
- Usage instructions
- Limitations and future improvements

### 6. `test-linux.sh` (New)
- Test script to verify Linux support
- Checks Node.js, npm, Chrome/Chromium installation
- Tests ego-browser wrapper and commands

## Usage Instructions

### Prerequisites
- Node.js 22 or later
- Chrome or Chromium browser
- npm (usually comes with Node.js)

### Installation

1. **Install Chrome/Chromium** (if not already installed):
   ```bash
   # Debian/Ubuntu
   sudo apt install google-chrome-stable
   
   # Fedora/RHEL
   sudo dnf install google-chrome-stable
   
   # Arch Linux
   sudo pacman -S chromium
   ```

2. **Run the install script**:
   ```bash
   sh skills/ego-browser/scripts/install.sh
   ```

3. **Add to PATH** (if not already done):
   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   ```

### Usage

1. **Start Chrome with remote debugging**:
   ```bash
   google-chrome --remote-debugging-port=9222
   ```

2. **Use ego-browser**:
   ```bash
   ego-browser nodejs <<'EOF'
   console.log('Hello from ego-browser!')
   EOF
   ```

3. **Check connection**:
   ```bash
   ego-browser --doctor
   ```

## Technical Details

### How the Wrapper Script Works

The wrapper script (`~/.local/bin/ego-browser`) does the following:

1. **Checks if Chrome is running with remote debugging** by trying to connect to `http://127.0.0.1:9222/json/version`

2. **Starts Chrome if not running** with the following flags:
   - `--remote-debugging-port=9222`: Enables remote debugging
   - `--user-data-dir=~/.ego-lite-chrome-profile`: Uses a separate profile
   - `--no-first-run`: Skips first-run dialogs
   - `--no-default-browser-check`: Doesn't check for default browser

3. **Connects to Chrome via WebSocket** using the debugging URL from `/json/version`

4. **Creates a `globalThis.ego` object** that provides the same API as the macOS version:
   - `sendCDPMessage()`: Sends CDP messages to Chrome
   - `onCDPMessage`: Callback for CDP messages
   - `listTabs()`: Lists open tabs
   - `listTaskSpaces()`: Lists task spaces (basic implementation)
   - `useTaskSpace()`: Selects a task space
   - `createTaskSpace()`: Creates a new task space
   - And more...

5. **Executes the user's JavaScript code** with the ego API available

### Chrome DevTools Protocol (CDP)

The Linux version uses CDP to control Chrome, which is the same protocol used by:
- Chrome DevTools
- Puppeteer
- Playwright
- The original ego-lite on macOS

CDP provides access to:
- Page navigation and manipulation
- DOM inspection and modification
- Network monitoring
- Console output
- And much more

## Limitations

### 1. Task Spaces
The Linux version has a basic implementation of task spaces. Full task space functionality requires the ego lite app, which is not available for Linux.

### 2. Chrome Data Migration
The Linux version cannot migrate Chrome data from an existing Chrome installation. You'll need to use a separate Chrome profile.

### 3. Agent Integration
Some agent-specific features may not work as well as on macOS since the Linux version uses a standard Chrome instance rather than the customized ego lite browser.

### 4. No Native Browser
The Linux version doesn't include a native browser like the macOS version. It relies on Chrome/Chromium being installed separately.

## Future Improvements

Potential improvements for the Linux version:

1. **Full Task Space Support**: Implement complete task space functionality
2. **Chrome Profile Migration**: Add support for migrating Chrome data
3. **Native Linux Browser**: If ego lite releases a native Linux version, update the installer
4. **GUI Integration**: Add system tray integration and notifications
5. **Package Distribution**: Create .deb, .rpm, and Flatpak packages
6. **Wayland Support**: Improve support for Wayland display server
7. **Performance Optimization**: Optimize the WebSocket connection and CDP communication

## Testing

To test the Linux version:

1. Run the test script: `./test-linux.sh`
2. Start Chrome with remote debugging: `google-chrome --remote-debugging-port=9222`
3. Test ego-browser: `ego-browser --doctor`
4. Run a simple script: `ego-browser nodejs <<'EOF' console.log('Test') EOF`

## Contributing

Contributions to improve Linux support are welcome. Please open an issue or pull request on the GitHub repository.

## License

This modified version is released under the same MIT License as the original ego-lite project.
