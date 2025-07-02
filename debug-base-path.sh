#!/bin/bash

# Debug Base Path Configuration
# This script helps diagnose issues with base path asset serving

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Display functions
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  IAMGickPro Base Path Debug Tool${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

print_step() {
    echo -e "${CYAN}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_warning "Running as root. Some tests may behave differently."
fi

print_header

# Get configuration from installer or prompt user
INSTALL_DIR="${1:-/var/www/html/iamgickpro}"
DOMAIN_NAME="${2:-localhost}"

if [[ ! -d "$INSTALL_DIR" ]]; then
    print_error "Installation directory not found: $INSTALL_DIR"
    echo "Usage: $0 [INSTALL_DIR] [DOMAIN_NAME]"
    echo "Example: $0 /var/www/html/iamgickpro example.com"
    exit 1
fi

# Read configuration from backend .env if available
ENV_FILE="$INSTALL_DIR/backend/.env"
if [[ -f "$ENV_FILE" ]]; then
    print_step "Reading configuration from: $ENV_FILE"
    
    # Source the .env file safely
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        if [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]]; then
            continue
        fi
        
        # Clean up the value (remove quotes)
        value=$(echo "$value" | sed 's/^["'\'']//' | sed 's/["'\'']$//')
        
        case "$key" in
            "BASE_PATH") BASE_PATH="$value" ;;
            "FRONTEND_URL") FRONTEND_URL="$value" ;;
            "BACKEND_URL") BACKEND_URL="$value" ;;
        esac
    done < "$ENV_FILE"
    
    print_success "Configuration loaded"
else
    print_warning "Backend .env file not found, using defaults"
    BASE_PATH=""
    FRONTEND_URL="http://$DOMAIN_NAME"
fi

# Display configuration
echo
print_step "Current Configuration:"
echo -e "  ${CYAN}Install Directory:${NC} $INSTALL_DIR"
echo -e "  ${CYAN}Domain Name:${NC} $DOMAIN_NAME"
echo -e "  ${CYAN}Base Path:${NC} ${BASE_PATH:-'(root installation)'}"
echo -e "  ${CYAN}Frontend URL:${NC} ${FRONTEND_URL:-"http://$DOMAIN_NAME"}"
echo

# Check webroot and files
WEBROOT="$INSTALL_DIR/public"
print_step "Checking webroot: $WEBROOT"

if [[ ! -d "$WEBROOT" ]]; then
    print_error "Webroot directory not found"
    exit 1
fi

if [[ ! -f "$WEBROOT/index.html" ]]; then
    print_error "index.html not found in webroot"
    exit 1
fi

print_success "Webroot and index.html found"

# Check index.html for base path configuration
print_step "Analyzing index.html for base path configuration"

if [[ -n "$BASE_PATH" && "$BASE_PATH" != "/" ]]; then
    # Should have base path configured
    expected_base="${BASE_PATH}/"
    if grep -q "base.*href.*$expected_base" "$WEBROOT/index.html" 2>/dev/null; then
        print_success "Base path correctly configured in index.html"
    else
        print_error "Base path NOT configured in index.html"
        echo "Expected base href: $expected_base"
        echo "Found in index.html:"
        grep -E "(base|href)" "$WEBROOT/index.html" | head -3 || echo "No base tag found"
        
        # Check if template wasn't processed
        if grep -q "%VITE_BASE_PATH%" "$WEBROOT/index.html" 2>/dev/null; then
            print_error "Vite template variable %VITE_BASE_PATH% was not replaced during build"
            echo "This indicates a build configuration issue"
        fi
    fi
else
    # Root installation, should have base href="/"
    if grep -q 'base.*href.*"/"' "$WEBROOT/index.html" 2>/dev/null; then
        print_success "Root installation correctly configured"
    else
        print_warning "Unexpected base configuration for root installation"
        grep -E "(base|href)" "$WEBROOT/index.html" | head -3 || echo "No base tag found"
        
        # Check if template wasn't processed
        if grep -q "%VITE_BASE_PATH%" "$WEBROOT/index.html" 2>/dev/null; then
            print_warning "Vite template variable %VITE_BASE_PATH% was not replaced during build"
        fi
    fi
fi

# Check assets directory
print_step "Checking assets directory"

if [[ -d "$WEBROOT/assets" ]]; then
    asset_count=$(find "$WEBROOT/assets" -type f | wc -l)
    print_success "Assets directory found with $asset_count files"
    
    echo "Sample assets:"
    find "$WEBROOT/assets" -type f | head -5 | while read -r file; do
        echo "  - ${file#$WEBROOT}"
    done
else
    print_error "Assets directory not found"
    echo "Directory contents:"
    ls -la "$WEBROOT"
fi

# Check nginx configuration
print_step "Checking nginx configuration"

NGINX_CONFIG="/etc/nginx/sites-available/iamgickpro"
if [[ -f "$NGINX_CONFIG" ]]; then
    print_success "Nginx configuration file found"
    
    # Check if it's enabled
    if [[ -L "/etc/nginx/sites-enabled/iamgickpro" ]]; then
        print_success "Nginx site is enabled"
    else
        print_error "Nginx site is NOT enabled"
    fi
    
    # Check for base path configuration
    if [[ -n "$BASE_PATH" && "$BASE_PATH" != "/" ]]; then
        if grep -q "$BASE_PATH" "$NGINX_CONFIG"; then
            print_success "Base path found in nginx configuration"
        else
            print_error "Base path NOT found in nginx configuration"
        fi
    fi
else
    print_error "Nginx configuration file not found"
fi

# Test nginx configuration
print_step "Testing nginx configuration"

if nginx -t 2>/dev/null; then
    print_success "Nginx configuration test passed"
else
    print_error "Nginx configuration test failed"
    echo "Run 'nginx -t' for details"
fi

# Test asset serving
print_step "Testing asset serving"

# Create a test asset
TEST_ASSET="$WEBROOT/assets/debug-test.txt"
mkdir -p "$(dirname "$TEST_ASSET")"
echo "Debug test file - $(date)" > "$TEST_ASSET"

# Construct test URL
if [[ -n "$BASE_PATH" && "$BASE_PATH" != "/" ]]; then
    test_url="http://localhost$BASE_PATH/assets/debug-test.txt"
else
    test_url="http://localhost/assets/debug-test.txt"
fi

echo "Testing asset URL: $test_url"

if curl -s -f "$test_url" > /dev/null 2>&1; then
    print_success "Asset serving test PASSED"
else
    print_error "Asset serving test FAILED"
    
    # Additional debugging
    echo
    print_step "Debugging asset serving failure"
    
    # Check if nginx is running
    if systemctl is-active nginx >/dev/null 2>&1; then
        print_success "Nginx is running"
    else
        print_error "Nginx is NOT running"
        echo "Start nginx with: systemctl start nginx"
    fi
    
    # Check recent nginx errors
    echo
    echo "Recent nginx error log entries:"
    tail -n 5 /var/log/nginx/imagepro_error.log 2>/dev/null || echo "No error log found"
    
    # Show curl details
    echo
    echo "Detailed curl test:"
    curl -I "$test_url" 2>&1 || echo "Curl failed"
fi

# Clean up test file
rm -f "$TEST_ASSET"

# Show troubleshooting tips
echo
print_step "Troubleshooting Tips"
echo
echo -e "${CYAN}1. Check nginx error log:${NC}"
echo "   tail -f /var/log/nginx/imagepro_error.log"
echo
echo -e "${CYAN}2. Verify asset files:${NC}"
echo "   ls -la $WEBROOT/assets/"
echo
echo -e "${CYAN}3. Test direct asset access:${NC}"
if [[ -n "$BASE_PATH" && "$BASE_PATH" != "/" ]]; then
    echo "   curl -I http://$DOMAIN_NAME$BASE_PATH/assets/"
else
    echo "   curl -I http://$DOMAIN_NAME/assets/"
fi
echo
echo -e "${CYAN}4. Check nginx configuration:${NC}"
echo "   nginx -T | grep -A 20 'server_name $DOMAIN_NAME'"
echo
echo -e "${CYAN}5. Restart services if needed:${NC}"
echo "   systemctl restart nginx"
echo "   systemctl restart php8.4-fpm"
echo

print_step "Debug completed"
