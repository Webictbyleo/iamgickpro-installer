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
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/iamgickpro-install.log"
readonly INSTALL_DIR="/var/www/html/iamgickpro"
readonly TEMP_DIR="/tmp/iamgickpro-install"
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
APP_NAME="IAMGickPro"
MAIL_FROM_ADDRESS=""
FRONTEND_URL=""
UNSPLASH_API_KEY=""
PEXELS_API_KEY=""
INSTALL_IMAGEMAGICK=true
INSTALL_FFMPEG=true
NODE_VERSION="21"

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
    echo
    echo -e "${YELLOW}Installation Directory:${NC} $INSTALL_DIR"
    echo -e "${YELLOW}Log File:${NC} $LOG_FILE"
    echo
    echo -e "${RED}⚠ WARNING:${NC} This installer will make system-wide changes."
    echo "   Make sure to backup your system before proceeding."
    echo
    
    while true; do
        read -p "Do you want to continue? (y/N): " -r
        case $REPLY in
            [Yy]*) break ;;
            [Nn]*|"") echo "Installation cancelled."; exit 0 ;;
            *) echo "Please answer yes or no." ;;
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

# Main installation orchestrator
main() {
    # Initialize
    check_root
    check_system
    create_directories
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
    echo "1. Configure your DNS to point to this server"
    echo "2. Set up SSL certificates (recommended: Let's Encrypt)"
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
