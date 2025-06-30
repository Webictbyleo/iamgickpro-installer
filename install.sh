#!/bin/bash

# IAMGickPro Production Installer
# A comprehensive installer for the IAMGickPro design platform
# 
# This script sets up a complete production environment including:
# - System dependencies (nginx, mysql, php 8.4)
# - Application setup (backend, frontend)
# - Database configuration and migration
# - Template and shape imports
# - Compiled dependencies (imagemagick, ffmpeg)
#
# Usage: sudo ./install.sh
#
# Author: IAMGickPro Development Team
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
readonly LOG_FILE="/var/log/iamgickpro-install.log"
readonly INSTALL_DIR="/var/www/html/iamgickpro"
readonly TEMP_DIR="/tmp/iamgickpro-install"
readonly CONFIG_CACHE="/var/cache/iamgickpro-installer"
readonly INSTALLER_REPO_URL="https://github.com/Webictbyleo/iamgickpro-installer.git"
readonly REPO_URL="https://github.com/Webictbyleo/iamgickpro.git"
readonly SHAPES_REPO_URL="https://github.com/Webictbyleo/design-vector-shapes.git"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Spinner characters
readonly SPINNER="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

# Global variables
MYSQL_ROOT_PASSWORD=""
DB_HOST="localhost"
DB_PORT="3306"
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
DOMAIN_NAME=""
ADMIN_EMAIL=""
ADMIN_PASSWORD=""
ADMIN_FIRST_NAME=""
ADMIN_LAST_NAME=""
APP_NAME="IAMGickPro"
MAIL_FROM_ADDRESS=""
FRONTEND_URL=""
BACKEND_URL=""
UNSPLASH_API_KEY=""
ICONFINDER_API_KEY=""
PEXELS_API_KEY=""
INSTALL_IMAGEMAGICK=true  # Required for image processing
INSTALL_FFMPEG=true       # Required for video processing
NODE_VERSION="21"         # LTS version used throughout the project

# Frontend change detection
FRONTEND_CHANGED=true     # Default to true for safety (build frontend if unsure)

# Phase tracking
declare -a COMPLETED_PHASES=()

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $*" | tee -a "$LOG_FILE"
}

# Display functions
print_header() {
    clear
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    IAMGickPro Installer                     ║"
    echo "║              Professional Design Platform                   ║"
    echo "║                        v1.0.0                               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

print_phase() {
    local phase="$1"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  Phase: ${BLUE}$phase${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

print_step() {
    local step="$1"
    echo -e "${YELLOW}▶ ${WHITE}$step${NC}"
}

print_success() {
    local message="$1"
    echo -e "${GREEN}✓ ${WHITE}$message${NC}"
}

print_error() {
    local message="$1"
    echo -e "${RED}✗ ${WHITE}$message${NC}"
}

print_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠ ${WHITE}$message${NC}"
}

# Spinner function
spinner() {
    local pid=$!
    local delay=0.1
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        printf "\r${BLUE}%s${NC} " "${SPINNER:$i:1}"
        sleep $delay
        i=$(( (i + 1) % ${#SPINNER} ))
    done
    printf "\r"
}

# Check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Auto-clone installer if phases are missing (for curl | bash usage)
ensure_installer_complete() {
    # Clean up old installer downloads first
    rm -rf "$TEMP_DIR"/installer* 2>/dev/null || true
    
    if [[ ! -d "$SCRIPT_DIR/phases" ]]; then
        echo
        print_step "Detected curl | bash installation"
        print_step "Downloading complete installer components"
        
        # Check if git is available
        if ! command -v git &> /dev/null; then
            print_step "Installing git (required for download)"
            apt-get update -qq
            apt-get install -y git
        fi
        
        # Clone the installer repository to temp location
        local installer_temp="$TEMP_DIR/installer"
        download_installer "$installer_temp"
        
        echo
    elif [[ "$SCRIPT_DIR" == *"/tmp/"* ]]; then
        # We're running from a temp directory, check for updates
        check_installer_updates
    fi
}

# Download installer components
download_installer() {
    local installer_temp="$1"
    
    print_step "Cloning installer repository"
    
    # Test GitHub connectivity first
    if ! curl -s --connect-timeout 10 https://github.com > /dev/null; then
        print_error "Cannot reach GitHub. Please check your internet connection."
        exit 1
    fi
    
    # Remove existing temp directory if it exists
    rm -rf "$installer_temp"
    
    # Try to clone the repository
    if git clone --quiet --depth 1 "$INSTALLER_REPO_URL" "$installer_temp" 2>/dev/null; then
        if [[ -d "$installer_temp/phases" ]]; then
            # Update SCRIPT_DIR to point to the complete installer
            SCRIPT_DIR="$installer_temp"
            print_success "Complete installer downloaded successfully"
            
            # Log the installer version if available
            if [[ -d "$installer_temp/.git" ]]; then
                local downloaded_version
                downloaded_version=$(cd "$installer_temp" && git rev-parse HEAD 2>/dev/null || echo "unknown")
                log "Downloaded installer version: ${downloaded_version:0:8}"
            fi
        else
            print_error "Downloaded installer is incomplete (missing phases)"
            exit 1
        fi
    else
        print_error "Failed to clone installer repository"
        print_error "Repository URL: $INSTALLER_REPO_URL"
        print_error "This might happen if:"
        print_error "1. The repository doesn't exist yet (you need to push it to GitHub)"
        print_error "2. The repository is private"
        print_error "3. Network connectivity issues"
        echo
        print_step "Attempting alternative download method..."
        
        # Try downloading as zip file instead
        local zip_url="https://github.com/Webictbyleo/iamgickpro-installer/archive/refs/heads/main.zip"
        if command -v wget &> /dev/null; then
            if wget -q "$zip_url" -O "$installer_temp.zip" 2>/dev/null; then
                if command -v unzip &> /dev/null || { apt-get install -y unzip &>/dev/null; }; then
                    unzip -q "$installer_temp.zip" -d "$(dirname "$installer_temp")" 2>/dev/null
                    mv "$(dirname "$installer_temp")/iamgickpro-installer-main" "$installer_temp" 2>/dev/null || true
                    if [[ -d "$installer_temp/phases" ]]; then
                        SCRIPT_DIR="$installer_temp"
                        print_success "Downloaded installer via zip archive"
                    else
                        print_error "Zip download failed or incomplete"
                        exit 1
                    fi
                else
                    print_error "Cannot install unzip utility"
                    exit 1
                fi
            else
                print_error "Alternative download also failed"
                exit 1
            fi
        else
            print_error "wget not available for alternative download"
            exit 1
        fi
    fi
}

# Check for installer updates
check_installer_updates() {
    # Skip update check if requested
    if [[ "${SKIP_UPDATE_CHECK:-false}" == "true" ]]; then
        print_step "Skipping installer update check (--skip-update-check)"
        return 0
    fi
    
    print_step "Checking for installer updates"
    
    # Get current installer version/commit hash if available
    local current_version=""
    if [[ -d "$SCRIPT_DIR/.git" ]]; then
        current_version=$(cd "$SCRIPT_DIR" && git rev-parse HEAD 2>/dev/null || echo "unknown")
    fi
    
    # Get latest version from remote
    local latest_version=""
    if command -v git &> /dev/null && curl -s --connect-timeout 10 https://github.com > /dev/null; then
        latest_version=$(git ls-remote "$INSTALLER_REPO_URL" HEAD 2>/dev/null | cut -f1 || echo "unknown")
    fi
    
    # Force update if requested
    if [[ "${FORCE_UPDATE_INSTALLER:-false}" == "true" ]]; then
        print_step "Force updating installer (--update-installer)"
        local new_installer="$TEMP_DIR/installer-updated"
        download_installer "$new_installer"
        print_success "Installer forcefully updated"
        return 0
    fi
    
    if [[ -n "$latest_version" && "$latest_version" != "unknown" && "$current_version" != "unknown" ]]; then
        if [[ "$current_version" != "$latest_version" ]]; then
            print_warning "Installer updates available!"
            echo
            echo -e "${CYAN}Current version:${NC} ${current_version:0:8}"
            echo -e "${CYAN}Latest version:${NC} ${latest_version:0:8}"
            echo
            echo -e "${YELLOW}TIP:${NC} Use --update-installer to force update or --skip-update-check to skip this check"
            echo
            
            while true; do
                printf "Download latest installer version? (Y/n): "
                read -r REPLY </dev/tty
                echo
                case $REPLY in
                    [Yy]*|"") 
                        print_step "Downloading latest installer"
                        local new_installer="$TEMP_DIR/installer-updated"
                        download_installer "$new_installer"
                        print_success "Updated installer downloaded"
                        break
                        ;;
                    [Nn]*) 
                        print_warning "Continuing with current installer version"
                        log_warning "User chose to continue with outdated installer"
                        break
                        ;;
                    *) 
                        echo "Please answer yes (y) or no (n)." 
                        ;;
                esac
            done
        else
            print_success "Installer is up to date"
        fi
    else
        print_warning "Could not check for updates (network or git issue)"
        log_warning "Update check failed: current=$current_version, latest=$latest_version"
    fi
}

# Check system requirements
check_system() {
    print_step "Checking system requirements"
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine operating system"
        exit 1
    fi
    
    source /etc/os-release
    
    case "$ID" in
        ubuntu)
            if [[ "${VERSION_ID}" < "20.04" ]]; then
                print_error "Ubuntu 20.04 or later is required"
                exit 1
            fi
            ;;
        debian)
            if [[ "${VERSION_ID}" < "11" ]]; then
                print_error "Debian 11 or later is required"
                exit 1
            fi
            ;;
        centos|rhel|fedora)
            print_warning "CentOS/RHEL/Fedora support is experimental"
            ;;
        *)
            print_error "Unsupported operating system: $ID"
            exit 1
            ;;
    esac
    
    print_success "System requirements check passed"
}

# Create installation directories
create_directories() {
    print_step "Creating installation directories"
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$TEMP_DIR"
    mkdir -p "$CONFIG_CACHE"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    print_success "Directories created"
}

# Show welcome message and get user consent
show_welcome() {
    print_header
    
    echo -e "${WHITE}Welcome to the IAMGickPro Production Installer!${NC}"
    echo
    echo "This installer will set up a complete production environment for"
    echo "the IAMGickPro design platform including:"
    echo
    echo -e "${CYAN}• System Dependencies:${NC} nginx, MySQL, PHP 8.4"
    echo -e "${CYAN}• Application Setup:${NC} Backend API, Frontend UI"
    echo -e "${CYAN}• Database:${NC} Schema creation and migration"
    echo -e "${CYAN}• Content:${NC} Template and shape imports"
    echo -e "${CYAN}• Media Processing:${NC} ImageMagick, FFmpeg (compiled from source)"
    echo -e "${CYAN}• Runtime:${NC} Node.js 22 (current LTS)"
    echo
    echo -e "${YELLOW}Installation Directory:${NC} $INSTALL_DIR"
    echo -e "${YELLOW}Log File:${NC} $LOG_FILE"
    echo -e "${YELLOW}Configuration Cache:${NC} $CONFIG_CACHE"
    echo
    
    # Show cache status
    if [[ -f "$CONFIG_CACHE/config.env" ]]; then
        echo -e "${GREEN}✓${NC} Configuration cache available (use --clear-cache to reset)"
    else
        echo -e "${YELLOW}ℹ${NC} No configuration cache found"
    fi
    echo
    echo -e "${RED}⚠ WARNING:${NC} This installer will make system-wide changes."
    echo "   Make sure to backup your system before proceeding."
    echo
    
    while true; do
        printf "Do you want to continue? (y/N): "
        read -r REPLY </dev/tty
        echo  # Add newline after user input
        case $REPLY in
            [Yy]*) 
                echo "Proceeding with installation..."
                break 
                ;;
            [Nn]*|"") 
                echo "Installation cancelled."
                exit 0 
                ;;
            *) 
                echo "Please answer yes (y) or no (n)." 
                ;;
        esac
    done
    
    echo
    print_success "Installation confirmed"
}

# Mark phase as completed
mark_phase_completed() {
    local phase="$1"
    COMPLETED_PHASES+=("$phase")
    log_success "Phase completed: $phase"
}

# Check if phase is completed
is_phase_completed() {
    local phase="$1"
    for completed in "${COMPLETED_PHASES[@]}"; do
        if [[ "$completed" == "$phase" ]]; then
            return 0
        fi
    done
    return 1
}

# Show help information
show_help() {
    echo "IAMGickPro Production Installer v1.0.0"
    echo
    echo "Usage: sudo ./install.sh [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  --clear-cache       Clear cached configuration and start fresh"
    echo "  --show-cache        Display current cached configuration"
    echo "  --force-reinstall   Force reinstallation of all components"
    echo "  --update-installer  Force update the installer to latest version"
    echo "  --skip-update-check Skip checking for installer updates"
    echo
    echo "Examples:"
    echo "  sudo ./install.sh                   # Normal installation"
    echo "  sudo ./install.sh --clear-cache     # Clear cache and reconfigure"
    echo "  sudo ./install.sh --show-cache      # Show cached settings"
    echo "  sudo ./install.sh --update-installer # Force installer update"
    echo
}

# Handle command line arguments
handle_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --clear-cache)
                print_step "Clearing cached configuration"
                rm -rf "$CONFIG_CACHE"
                print_success "Configuration cache cleared"
                exit 0
                ;;
            --show-cache)
                if [[ -f "$CONFIG_CACHE/config.env" ]]; then
                    echo -e "${CYAN}Cached Configuration:${NC}"
                    echo
                    grep -E '^[A-Z_]+=' "$CONFIG_CACHE/config.env" | grep -v PASSWORD | while IFS='=' read -r key value; do
                        echo -e "${CYAN}$key:${NC} ${value//\"/}"
                    done
                    echo
                    echo -e "${YELLOW}Note: Passwords are hidden for security${NC}"
                    echo -e "${CYAN}Cache location:${NC} $CONFIG_CACHE/config.env"
                    echo -e "${CYAN}Last modified:${NC} $(date -r "$CONFIG_CACHE/config.env" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'unknown')"
                else
                    echo -e "${YELLOW}No cached configuration found${NC}"
                fi
                exit 0
                ;;
            --force-reinstall)
                export FORCE_REINSTALL=true
                print_warning "Force reinstall mode enabled"
                ;;
            --update-installer)
                export FORCE_UPDATE_INSTALLER=true
                print_step "Force installer update mode enabled"
                ;;
            --skip-update-check)
                export SKIP_UPDATE_CHECK=true
                print_step "Skipping installer update check"
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
        shift
    done
}

# Main installation orchestrator
main() {
    # Handle command line arguments first
    handle_arguments "$@"
    
    # Initialize
    check_root
    create_directories
    ensure_installer_complete
    check_system
    show_welcome
    
    # Start logging
    log "Starting IAMGickPro installation"
    log "System: $(uname -a)"
    log "User: $(whoami)"
    log "Installation directory: $INSTALL_DIR"
    
    # Installation phases (ordered by priority)
    local phases=(
        "user_input"
        "system_setup" 
        "clone_repository"
        "env_configuration"
        "backend_setup"
        "frontend_setup"
        "database_setup"
        "content_import"
        "media_dependencies"
        "final_configuration"
    )
    
    # Execute phases
    for phase in "${phases[@]}"; do
        if ! is_phase_completed "$phase"; then
            print_phase "$(echo "$phase" | tr '_' ' ' | tr '[:lower:]' '[:upper:]')"
            
            case "$phase" in
                "user_input") source "$SCRIPT_DIR/phases/01-user-input.sh" ;;
                "system_setup") source "$SCRIPT_DIR/phases/02-system-setup.sh" ;;
                "clone_repository") source "$SCRIPT_DIR/phases/03-clone-repository.sh" ;;
                "env_configuration") source "$SCRIPT_DIR/phases/04-env-configuration.sh" ;;
                "backend_setup") source "$SCRIPT_DIR/phases/05-backend-setup.sh" ;;
                "frontend_setup") source "$SCRIPT_DIR/phases/06-frontend-setup.sh" ;;
                "database_setup") source "$SCRIPT_DIR/phases/07-database-setup.sh" ;;
                "content_import") source "$SCRIPT_DIR/phases/08-content-import.sh" ;;
                "media_dependencies") source "$SCRIPT_DIR/phases/09-media-dependencies.sh" ;;
                "final_configuration") source "$SCRIPT_DIR/phases/10-final-configuration.sh" ;;
            esac
            
            mark_phase_completed "$phase"
        else
            print_success "Phase already completed: $phase"
        fi
    done
    
    # Installation complete
    print_header
    print_success "IAMGickPro installation completed successfully!"
    echo
    echo -e "${CYAN}Application URL:${NC} $FRONTEND_URL"
    echo -e "${CYAN}Admin Email:${NC} $ADMIN_EMAIL"
    echo -e "${CYAN}Admin Password:${NC} $ADMIN_PASSWORD"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "3. Review and customize the application settings"
    echo "4. Start creating amazing designs!"
    echo
    echo -e "${GREEN}Happy designing! 🎨${NC}"
    
    log_success "Installation completed successfully"
}

# Error handling
trap 'log_error "Installation failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"
