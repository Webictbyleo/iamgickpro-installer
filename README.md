# IAMGickPro Production Installer

A comprehensive installer for the IAMGickPro design platform that sets up a complete production environment.

## Features

- **Complete System Setup**: nginx, MySQL, PHP 8.4, Node.js
- **Application Deployment**: Backend API and Frontend UI
- **Custom Base Path Support**: Install at custom URL paths (e.g., `/image-editor`, `/design-tool`)
- **Database Migration**: Automatic schema creation and data import
- **Media Processing**: ImageMagick and FFmpeg compiled from source
- **SSL/TLS Setup**: Automatic certificate generation with Let's Encrypt
- **Content Import**: Templates and design shapes
- **Configuration Caching**: Save settings for multiple installations

## Quick Start

```bash
# Download and run installer
curl -fsSL https://raw.githubusercontent.com/Webictbyleo/iamgickpro-installer/main/install.sh | sudo bash

# Or clone and run locally
git clone https://github.com/Webictbyleo/iamgickpro-installer.git
cd iamgickpro-installer
sudo ./install.sh
```

## Base Path Support

IAMGickPro supports installation at custom URL paths:

- **Root Installation**: `https://example.com/` (default)
- **Subdirectory Installation**: `https://example.com/image-editor/`

This allows you to:
- Host alongside other applications
- Integrate into existing websites
- Create multi-tenant solutions

See [BASE_PATH_SUPPORT.md](BASE_PATH_SUPPORT.md) for detailed documentation.

## Command Line Options

```bash
sudo ./install.sh [OPTIONS]

Options:
  -h, --help               Show help message
  -d, --install-dir DIR    Set custom installation directory
  --clear-cache            Clear cached configuration
  --show-cache             Display current cached configuration
  --force-reinstall        Force reinstallation of all components
  --unattended             Run in unattended mode
```

## Requirements

- Ubuntu 20.04+ or Debian 11+
- Root access (sudo)
- 2GB+ available disk space
- Internet connection for downloads

## What Gets Installed

- **Web Server**: Nginx with optimized configuration
- **Database**: MySQL 8.0 with IAMGickPro schema
- **PHP**: Version 8.4 with required extensions
- **Node.js**: Version 21 (current LTS)
- **Media Processing**: ImageMagick and FFmpeg
- **Application**: IAMGickPro backend and frontend
- **Background Services**: Queue processing and cron jobs

## Configuration

The installer prompts for:
- Domain name
- Base path (optional)
- Database credentials
- Admin account details
- API keys for stock media (optional)

Configuration is cached for future installations.

## SSL/TLS Certificates

The installer automatically configures SSL certificates using Let's Encrypt if:
- Domain points to the server
- Ports 80/443 are accessible
- Certbot is available

## Support

- **Documentation**: See individual `.md` files in this repository
- **Issues**: Report bugs via GitHub issues
- **Support**: Contact the development team

## License

This installer is part of the IAMGickPro project. See LICENSE file for details.