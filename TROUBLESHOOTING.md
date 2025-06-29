# IAMGickPro Installer Troubleshooting

## Installation Hangs at Welcome Screen

If the installer displays the welcome message but doesn't show the continuation prompt:

### Option 1: Run Directly (Recommended)
```bash
# Download the installer
wget https://raw.githubusercontent.com/YOUR_USERNAME/iamgickpro-installer/main/install.sh

# Make it executable
chmod +x install.sh

# Run with sudo
sudo ./install.sh
```

### Option 2: Check Interactive Mode
```bash
# Test if your terminal supports interactive input
./test-input.sh
```

### Option 3: Force TTY Mode
```bash
# Run with explicit TTY
sudo bash -i install.sh
```

### Option 4: Manual Input
If the prompt doesn't appear, you can still type `y` and press Enter to continue.

## Common Issues

### Script Downloaded via curl/wget
When downloading and piping directly:
```bash
# DON'T: curl | bash (may not work interactively)
curl -fsSL https://example.com/install.sh | bash

# DO: Download first, then run
curl -fsSL https://example.com/install.sh -o install.sh
chmod +x install.sh
sudo ./install.sh
```

### Permission Issues
```bash
# Ensure script is executable
chmod +x install.sh

# Run with proper permissions
sudo ./install.sh
```

### SSH/Remote Sessions
```bash
# Use proper SSH flags for interactive sessions
ssh -t user@server 'sudo ./install.sh'
```

## Debug Mode

To run with debug output:
```bash
# Enable debug mode
bash -x install.sh

# Or set debug flag
set -x
./install.sh
```

## Log Files

Check installation logs:
```bash
# View installation log
tail -f /var/log/iamgickpro-install.log

# Check system logs
journalctl -f
```
