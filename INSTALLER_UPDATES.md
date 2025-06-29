# IAMGickPro Installer Auto-Update Feature

## Overview
The IAMGickPro installer now includes intelligent auto-update functionality to ensure you always have the latest installation scripts and bug fixes.

## How It Works

### 1. **Automatic Update Detection**
When you run the installer via `curl | bash`, it will:
- Download the latest installer components
- Check if you're running from a temporary directory (indicating curl | bash usage)
- Compare your current installer version with the latest available on GitHub
- Prompt you to update if a newer version is available

### 2. **Update Mechanisms**

#### For `curl | bash` Usage:
```bash
curl -fsSL https://raw.githubusercontent.com/Webictbyleo/iamgickpro-installer/main/install.sh | bash
```
- Always downloads fresh installer components
- Automatically checks for updates
- Prompts user to download latest version if updates are available

#### For Local Installation:
```bash
# Download and run locally
git clone https://github.com/Webictbyleo/iamgickpro-installer.git
cd iamgickpro-installer
sudo ./install.sh
```
- Still checks for updates when running from temp directories
- Provides update options

### 3. **Command Line Options**

```bash
# Force update the installer before proceeding
sudo ./install.sh --update-installer

# Skip the update check entirely
sudo ./install.sh --skip-update-check

# Show help with all options
sudo ./install.sh --help
```

### 4. **Update Process**
1. **Version Check**: Compares current commit hash with latest GitHub commit
2. **User Prompt**: Asks if you want to download the latest version
3. **Fresh Download**: Downloads latest installer to a new temporary directory
4. **Seamless Transition**: Switches to the updated installer automatically

## Benefits

### ✅ **Always Current**
- Get the latest bug fixes and improvements
- Ensure compatibility with newer system versions
- Access new features as they're released

### ✅ **User Control**
- Choose whether to update or continue with current version
- Force updates when needed
- Skip update checks for automated deployments

### ✅ **Reliable**
- Fallback mechanisms for network issues
- Clean temporary directory management
- Detailed logging of update process

## Examples

### Normal Usage (with Update Check)
```bash
curl -fsSL https://raw.githubusercontent.com/Webictbyleo/iamgickpro-installer/main/install.sh | bash
```
Output:
```
▶ Checking for installer updates
⚠ Installer updates available!

Current version: a1b2c3d4
Latest version: e5f6g7h8

TIP: Use --update-installer to force update or --skip-update-check to skip this check

Download latest installer version? (Y/n): y
▶ Downloading latest installer
✓ Updated installer downloaded
```

### Force Update
```bash
curl -fsSL https://raw.githubusercontent.com/Webictbyleo/iamgickpro-installer/main/install.sh | bash -s -- --update-installer
```

### Skip Update Check (for Automation)
```bash
curl -fsSL https://raw.githubusercontent.com/Webictbyleo/iamgickpro-installer/main/install.sh | bash -s -- --skip-update-check
```

## Technical Details

### Version Detection
- Uses `git rev-parse HEAD` to get current commit hash
- Uses `git ls-remote` to get latest remote commit hash
- Compares first 8 characters of commit hashes

### Download Process
- Cleans up old temporary installer downloads
- Uses `git clone --depth 1` for efficient downloads
- Falls back to ZIP download if git fails
- Validates downloaded components before proceeding

### Security
- Only downloads from official GitHub repository
- Validates installer completeness before use
- Maintains existing security practices

## Troubleshooting

### Update Check Fails
If update checking fails, the installer will:
- Log the failure reason
- Continue with the current version
- Display a warning message

### Network Issues
- Installer continues with current version if network is unavailable
- Provides clear error messages
- Suggests using `--skip-update-check` for offline scenarios

### Manual Update
If automatic updates don't work, you can always:
```bash
# Clear cache and download fresh
curl -fsSL https://raw.githubusercontent.com/Webictbyleo/iamgickpro-installer/main/install.sh | bash -s -- --clear-cache --update-installer
```

This ensures you're always running the most current and reliable version of the IAMGickPro installer!
