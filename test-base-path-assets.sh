#!/bin/bash

# Test Base Path Asset Loading
# This script helps test and debug base path asset issues

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  Base Path Asset Loading Test${NC}"
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

print_header

INSTALL_DIR="${1:-/var/www/html/iamgickpro}"
DOMAIN="${2:-localhost}"

if [[ ! -d "$INSTALL_DIR" ]]; then
    print_error "Installation directory not found: $INSTALL_DIR"
    exit 1
fi

# Get configuration
WEBROOT="$INSTALL_DIR/public"
BACKEND_ENV="$INSTALL_DIR/backend/.env"

if [[ -f "$BACKEND_ENV" ]]; then
    BASE_PATH=$(grep '^BASE_PATH=' "$BACKEND_ENV" | cut -d'=' -f2 | tr -d '"' || echo "")
    FRONTEND_URL=$(grep '^FRONTEND_URL=' "$BACKEND_ENV" | cut -d'=' -f2 | tr -d '"' || echo "")
else
    print_warning "Backend .env not found, using defaults"
    BASE_PATH=""
    FRONTEND_URL="http://$DOMAIN"
fi

print_step "Configuration:"
echo "  Install Dir: $INSTALL_DIR"
echo "  Webroot: $WEBROOT"
echo "  Base Path: '${BASE_PATH:-'(root)'}'"
echo "  Frontend URL: $FRONTEND_URL"
echo

# Check index.html
print_step "Analyzing index.html"

if [[ ! -f "$WEBROOT/index.html" ]]; then
    print_error "index.html not found"
    exit 1
fi

echo "Base tag in index.html:"
grep -E '<base[^>]*>' "$WEBROOT/index.html" || echo "No base tag found"

echo
echo "Asset references in index.html:"
grep -oE 'src="[^"]*"' "$WEBROOT/index.html" | head -5
echo
grep -oE 'href="[^"]*\.css"' "$WEBROOT/index.html" | head -3

# Test actual asset URLs
print_step "Testing asset URLs"

# Find an actual JS file
js_file=$(find "$WEBROOT/assets" -name "*.js" -type f | head -1 2>/dev/null || echo "")
css_file=$(find "$WEBROOT/assets" -name "*.css" -type f | head -1 2>/dev/null || echo "")

if [[ -n "$js_file" ]]; then
    js_filename=$(basename "$js_file")
    
    # Test different URL patterns
    if [[ -n "$BASE_PATH" && "$BASE_PATH" != "/" ]]; then
        # Test base path URL
        base_path_url="http://$DOMAIN$BASE_PATH/assets/$js_filename"
        root_url="http://$DOMAIN/assets/$js_filename"
        
        echo "Testing base path URL: $base_path_url"
        if curl -s -I "$base_path_url" | grep -q "200 OK"; then
            print_success "Base path URL works"
        else
            print_error "Base path URL failed"
        fi
        
        echo "Testing root URL: $root_url"
        if curl -s -I "$root_url" | grep -q "200 OK"; then
            print_warning "Root URL works (but should not for subdirectory install)"
        else
            print_success "Root URL correctly blocked"
        fi
    else
        # Root installation
        root_url="http://$DOMAIN/assets/$js_filename"
        echo "Testing root URL: $root_url"
        if curl -s -I "$root_url" | grep -q "200 OK"; then
            print_success "Root URL works"
        else
            print_error "Root URL failed"
        fi
    fi
else
    print_warning "No JS files found in assets directory"
fi

# Check what URLs are actually in the HTML
print_step "Analyzing asset URLs in index.html"

if [[ -n "$BASE_PATH" && "$BASE_PATH" != "/" ]]; then
    expected_prefix="$BASE_PATH/"
    
    if grep -q "src=\"$expected_prefix" "$WEBROOT/index.html"; then
        print_success "Assets use correct base path prefix"
    else
        print_error "Assets do NOT use base path prefix"
        echo "Expected assets to start with: $expected_prefix"
        echo "Found asset URLs:"
        grep -oE 'src="[^"]*assets/[^"]*"' "$WEBROOT/index.html" | head -3
    fi
else
    if grep -q 'src="/assets/' "$WEBROOT/index.html"; then
        print_success "Assets use root path (correct for root installation)"
    else
        print_error "Assets do not use expected root path"
    fi
fi

# Show detailed diagnosis
echo
print_step "Detailed Diagnosis"

echo "1. Check Vite build configuration:"
if [[ -f "$INSTALL_DIR/frontend/.env" ]]; then
    echo "   VITE_BASE_PATH: $(grep '^VITE_BASE_PATH=' "$INSTALL_DIR/frontend/.env" | cut -d'=' -f2 || echo 'NOT SET')"
else
    echo "   Frontend .env not found"
fi

echo "2. Expected vs Actual:"
if [[ -n "$BASE_PATH" && "$BASE_PATH" != "/" ]]; then
    echo "   Expected asset URL: $FRONTEND_URL/assets/filename.js"
    echo "   Expected src attribute: src=\"$BASE_PATH/assets/filename.js\""
else
    echo "   Expected asset URL: http://$DOMAIN/assets/filename.js"
    echo "   Expected src attribute: src=\"/assets/filename.js\""
fi

echo "3. Nginx configuration check:"
if nginx -T 2>/dev/null | grep -A 10 -B 5 "assets" | head -15; then
    echo "   Nginx asset configuration found above"
else
    echo "   No nginx asset configuration found"
fi

echo
print_step "Recommendations"

if grep -q 'src="/assets/' "$WEBROOT/index.html" && [[ -n "$BASE_PATH" && "$BASE_PATH" != "/" ]]; then
    echo "ISSUE: Assets are using root paths instead of base path"
    echo "CAUSE: Vite build did not apply base path to assets"
    echo "SOLUTION:"
    echo "  1. Check frontend/.env file has correct VITE_BASE_PATH"
    echo "  2. Rebuild frontend with: cd frontend && npm run build"
    echo "  3. Ensure vite.config.ts has correct base path configuration"
fi

echo
print_step "Testing complete"
