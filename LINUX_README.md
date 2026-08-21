# ego-lite Linux Version

> Unofficial, community-maintained Linux port of [citrolabs/ego-lite](https://github.com/citrolabs/ego-lite). Not affiliated with or endorsed by CitroLabs.

This is a modified version of ego-lite that supports Linux systems.

## Overview

ego-lite is a browser designed for AI agents to run browser automation. The original version only supports macOS, but this modified version adds Linux support by using Chrome/Chromium with remote debugging.

## How It Works

On Linux, ego-browser works by:

1. Connecting to a Chrome/Chromium instance running with remote debugging
2. Using the Chrome DevTools Protocol (CDP) to control the browser
3. Providing the same API as the macOS version through a wrapper script

## Prerequisites

- **Node.js 22 or later**
- **Chrome or Chromium browser**
- **npm** (usually comes with Node.js)

## Installation

### 1. Install Chrome/Chromium

**Debian/Ubuntu:**
```bash
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
sudo sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list'
sudo apt update
sudo apt install google-chrome-stable
```

**Fedora/RHEL:**
```bash
sudo dnf install google-chrome-stable
```

**Arch Linux:**
```bash
sudo pacman -S chromium
```

### 2. Install ego-browser

Run the install script:
```bash
sh skills/ego-browser/scripts/install.sh
```

Or use the Linux-specific script:
```bash
sh skills/ego-browser/scripts/install-linux.sh
```

### 3. Add to PATH

Make sure `~/.local/bin` is in your PATH:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add this to your `~/.bashrc` or `~/.zshrc` to make it permanent.

## Usage

### 1. Start Chrome with Remote Debugging

Before using ego-browser, start Chrome with remote debugging enabled:

```bash
google-chrome --remote-debugging-port=9222
```

Or if you want to use a separate profile:
```bash
google-chrome --remote-debugging-port=9222 --user-data-dir=~/.ego-lite-chrome-profile
```

### 2. Use ego-browser

Once Chrome is running with remote debugging, you can use ego-browser:

```bash
ego-browser nodejs <<'EOF'
console.log('Hello from ego-browser!')
EOF
```

### 3. Check Browser Connection

To verify that ego-browser can connect to Chrome:

```bash
ego-browser --doctor
```

## Environment Variables

- `EGO_BROWSER_CHROME_PATH`: Path to Chrome/Chromium executable (default: auto-detect)
- `EGO_BROWSER_DEBUGGING_PORT`: Chrome debugging port (default: 9222)

## Example Usage

### Take a Screenshot

```bash
ego-browser nodejs <<'EOF'
const { page } = require('./helpers');

async function takeScreenshot() {
    await page.goto('https://example.com');
    await page.waitForLoadState();
    const screenshot = await page.screenshot();
    console.log('Screenshot taken');
}

takeScreenshot().catch(console.error);
EOF
```

### Interact with a Page

```bash
ego-browser nodejs <<'EOF'
const { page, click, fill } = require('./helpers');

async function interactWithPage() {
    await page.goto('https://example.com');
    await page.waitForLoadState();
    
    // Click on an element
    await click('button[type="submit"]');
    
    // Fill in a form
    await fill('input[name="email"]', 'user@example.com');
    
    console.log('Page interaction completed');
}

interactWithPage().catch(console.error);
EOF
```

## Differences from macOS Version

| Feature | macOS | Linux |
|---------|-------|-------|
| Browser | ego lite app (Chromium-based) | Chrome/Chromium with remote debugging |
| Task Spaces | Native support | Limited (basic implementation) |
| Chrome Data Migration | Supported | Not supported (separate profile) |
| Installation | DMG installer | Manual Chrome setup + wrapper script |

## Limitations

1. **Task Spaces**: The Linux version has a basic implementation of task spaces. Full task space functionality requires the ego lite app.

2. **Chrome Data Migration**: The Linux version cannot migrate Chrome data from an existing Chrome installation. You'll need to use a separate Chrome profile.

3. **Agent Integration**: Some agent-specific features may not work as well as on macOS since the Linux version uses a standard Chrome instance rather than the customized ego lite browser.

## Troubleshooting

### Chrome Not Found

If ego-browser reports that Chrome is not found:
1. Make sure Chrome or Chromium is installed
2. Check the installation path with `which google-chrome` or `which chromium`
3. Set the `EGO_BROWSER_CHROME_PATH` environment variable if Chrome is in a non-standard location

### Connection Failed

If ego-browser cannot connect to Chrome:
1. Make sure Chrome is running with remote debugging enabled
2. Check that port 9222 is not blocked by a firewall
3. Try restarting Chrome with the debugging flag

### Permission Denied

If you get permission errors when running the wrapper script:
```bash
chmod +x ~/.local/bin/ego-browser
```

## Contributing

If you find issues with the Linux version or want to contribute improvements, please open an issue on the GitHub repository.

## License

This modified version is released under the same MIT License as the original ego-lite project.
