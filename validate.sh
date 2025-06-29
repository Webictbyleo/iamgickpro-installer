#!/bin/bash

# IAMGickPro Installer Validation Script
# Validates the installer structure and dependencies before running

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ERRORS=0

print_status() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((ERRORS++))
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo "IAMGickPro Installer Validation"
echo "==============================="
echo

# Check if running as root
print_status "Checking user privileges"
if [[ $EUID -eq 0 ]]; then
    print_success "Running as root"
else
    print_error "Must run as root (use sudo)"
fi

# Check required directories
print_status "Checking installer structure"

REQUIRED_DIRS=(
    "scripts/installer"
    "scripts/installer/phases"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [[ -d "$SCRIPT_DIR/$dir" ]]; then
        print_success "Directory exists: $dir"
    else
        print_error "Missing directory: $dir"
    fi
done

# Check required phase scripts
print_status "Checking phase scripts"

REQUIRED_PHASES=(
    "01-user-input.sh"
    "02-system-setup.sh"
    "03-clone-repository.sh"
    "04-env-configuration.sh"
    "05-backend-setup.sh"
    "06-frontend-setup.sh"
    "07-database-setup.sh"
    "08-content-import.sh"
    "09-media-dependencies.sh"
    "10-final-configuration.sh"
)

for phase in "${REQUIRED_PHASES[@]}"; do
    phase_file="$SCRIPT_DIR/scripts/installer/phases/$phase"
    if [[ -f "$phase_file" && -x "$phase_file" ]]; then
        print_success "Phase script: $phase"
    elif [[ -f "$phase_file" ]]; then
        print_warning "Phase script not executable: $phase"
        chmod +x "$phase_file"
        print_success "Made executable: $phase"
    else
        print_error "Missing phase script: $phase"
    fi
done

# Check main installer script
print_status "Checking main installer"

MAIN_INSTALLER="$SCRIPT_DIR/scripts/installer/install.sh"
if [[ -f "$MAIN_INSTALLER" && -x "$MAIN_INSTALLER" ]]; then
    print_success "Main installer script exists and is executable"
else
    print_error "Main installer script missing or not executable"
fi

# Check system requirements
print_status "Checking system requirements"

# Check OS
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    case "$ID" in
        ubuntu)
            if [[ "${VERSION_ID}" < "20.04" ]]; then
                print_warning "Ubuntu 20.04+ recommended (found $VERSION_ID)"
            else
                print_success "Operating system: Ubuntu $VERSION_ID"
            fi
            ;;
        debian)
            if [[ "${VERSION_ID}" < "11" ]]; then
                print_warning "Debian 11+ recommended (found $VERSION_ID)"
            else
                print_success "Operating system: Debian $VERSION_ID"
            fi
            ;;
        *)
            print_warning "Unsupported/untested OS: $ID"
            ;;
    esac
else
    print_error "Cannot determine operating system"
fi

# Check internet connectivity
print_status "Checking internet connectivity"
if curl -s --connect-timeout 5 https://github.com > /dev/null; then
    print_success "Internet connectivity available"
else
    print_error "No internet connectivity - required for downloading dependencies"
fi

# Check disk space
print_status "Checking disk space"
AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
REQUIRED_SPACE=20971520  # 20GB in KB

if [[ $AVAILABLE_SPACE -gt $REQUIRED_SPACE ]]; then
    print_success "Sufficient disk space available ($(($AVAILABLE_SPACE/1024/1024))GB)"
else
    print_warning "Low disk space - recommend 20GB+ free ($(($AVAILABLE_SPACE/1024/1024))GB available)"
fi

# Check memory
print_status "Checking system memory"
AVAILABLE_MEMORY=$(free -m | awk 'NR==2{print $2}')
REQUIRED_MEMORY=2048

if [[ $AVAILABLE_MEMORY -gt $REQUIRED_MEMORY ]]; then
    print_success "Sufficient memory available (${AVAILABLE_MEMORY}MB)"
else
    print_warning "Low memory - recommend 2GB+ RAM (${AVAILABLE_MEMORY}MB available)"
fi

# Check for conflicting services
print_status "Checking for conflicting services"

CONFLICTING_SERVICES=("apache2" "httpd")

for service in "${CONFLICTING_SERVICES[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        print_warning "Conflicting service running: $service (consider stopping before installation)"
    fi
done

# Summary
echo
echo "Validation Summary"
echo "=================="

if [[ $ERRORS -eq 0 ]]; then
    print_success "All validation checks passed!"
    echo
    echo -e "${GREEN}The installer is ready to run.${NC}"
    echo "To start installation: sudo ./install.sh"
else
    print_error "Found $ERRORS error(s) that must be resolved before installation"
    echo
    echo -e "${RED}Please fix the errors above before running the installer.${NC}"
    exit 1
fi
