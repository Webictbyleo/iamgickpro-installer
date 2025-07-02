# Base Path Asset Serving Fix - Complete

## Issue Description
After installation with a custom base path (e.g., `https://example.com/product-1`), users experienced a blank page because assets (JS, CSS files) were not loading properly. Only the index.html file was being served correctly.

## Root Cause Analysis
The nginx configuration for subdirectory installations had several issues:

1. **Improper asset handling**: The `alias` directive was causing path resolution issues for assets
2. **Missing specific asset location blocks**: Assets needed dedicated nginx location blocks to be served correctly  
3. **Base path normalization**: Environment variables weren't properly normalized for Vite builds
4. **Lack of debugging tools**: No easy way to diagnose base path configuration issues

## Solution Implemented

### 1. Fixed Nginx Configuration (`phases/06-frontend-setup.sh`)

**Before (Problematic):**
```nginx
location $BASE_PATH {
    alias $webroot;
    index index.html;
    try_files $uri $uri/ @iamgickpro_fallback;
    
    # Handle assets properly
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}

location @iamgickpro_fallback {
    rewrite ^.*$ $BASE_PATH/index.html last;
}
```

**After (Fixed):**
```nginx
# IAMGickPro frontend assets (served with base path)
location ~ ^$BASE_PATH/assets/(.*)$ {
    root $webroot;
    try_files /assets/$1 =404;
    expires 1y;
    add_header Cache-Control "public, immutable";
    
    # CORS headers for fonts and other assets
    add_header Access-Control-Allow-Origin "*";
    add_header Access-Control-Allow-Methods "GET, OPTIONS";
    add_header Access-Control-Allow-Headers "Range, Content-Type";
}

# IAMGickPro static files (favicon, manifest, etc.)
location ~ ^$BASE_PATH/(favicon\.ico|manifest\.json|robots\.txt|.*\.(png|jpg|jpeg|gif|svg|webp|ico))$ {
    root $webroot;
    try_files /$1 =404;
    expires 1d;
    add_header Cache-Control "public";
}

# IAMGickPro application at custom base path
location $BASE_PATH {
    root $webroot;
    index index.html;
    try_files $uri $uri/ @iamgickpro_fallback;
}

# Fallback for SPA routing
location @iamgickpro_fallback {
    root $webroot;
    try_files /index.html =404;
}
```

### 2. Improved Environment Configuration (`phases/04-env-configuration.sh`)

Added proper base path normalization:

```bash
# Normalize base path for Vite (ensure it starts with / and doesn't end with / unless it's root)
local vite_base_path="/"
if [[ -n "$BASE_PATH" && "$BASE_PATH" != "/" ]]; then
    # Ensure base path starts with /
    if [[ "${BASE_PATH:0:1}" != "/" ]]; then
        BASE_PATH="/$BASE_PATH"
    fi
    # Remove trailing slash if present (unless it's just "/")
    if [[ "${BASE_PATH: -1}" == "/" && ${#BASE_PATH} -gt 1 ]]; then
        BASE_PATH="${BASE_PATH%/}"
    fi
    vite_base_path="$BASE_PATH/"
fi
```

### 3. Enhanced Build Validation (`phases/06-frontend-setup.sh`)

Added comprehensive validation for:
- Environment configuration display
- Build output verification
- Base path configuration in built files
- Asset file detection

### 4. Created Debug Tool (`debug-base-path.sh`)

A standalone script that helps diagnose base path configuration issues:
- Analyzes current configuration
- Tests asset serving
- Provides troubleshooting tips
- Validates nginx configuration

## Key Changes Summary

### Nginx Configuration Improvements
1. **Specific asset location blocks**: Created dedicated regex location blocks for `/assets/` and static files
2. **Proper root directive**: Replaced problematic `alias` with `root` directive for better path resolution
3. **CORS headers**: Added necessary CORS headers for asset serving
4. **Better fallback handling**: Improved SPA routing fallback mechanism

### Environment Variable Fixes
1. **Base path normalization**: Ensures proper formatting of VITE_BASE_PATH
2. **Trailing slash handling**: Vite expects base path to end with `/` for proper asset URL generation

### Enhanced Debugging
1. **Build-time validation**: Verifies base path configuration during build
2. **Deployment validation**: Checks asset serving after deployment
3. **Standalone debug tool**: Provides comprehensive troubleshooting capabilities

## Testing the Fix

### Automatic Testing
The installer now includes:
1. Environment configuration validation
2. Build output verification  
3. Asset serving tests
4. Base path configuration validation

### Manual Testing
Use the debug script:
```bash
sudo ./debug-base-path.sh [INSTALL_DIR] [DOMAIN_NAME]
```

### Quick Verification
1. Check if assets load in browser
2. Verify network tab shows assets loading from correct URLs
3. Test SPA routing works properly

## Troubleshooting Guide

### If Assets Still Don't Load

1. **Run the debug script:**
   ```bash
   sudo ./debug-base-path.sh
   ```

2. **Check nginx error log:**
   ```bash
   tail -f /var/log/nginx/imagepro_error.log
   ```

3. **Verify asset files exist:**
   ```bash
   ls -la /var/www/html/iamgickpro/public/assets/
   ```

4. **Test asset URL manually:**
   ```bash
   curl -I http://yourdomain.com/your-base-path/assets/index-[hash].js
   ```

5. **Restart services:**
   ```bash
   systemctl restart nginx
   systemctl restart php8.4-fpm
   ```

### Common Issues and Solutions

1. **404 on assets**: Usually nginx configuration issue - check location blocks
2. **Blank page but index.html loads**: Assets not being served - verify asset location blocks
3. **Wrong asset URLs**: Base path not properly configured in Vite - check VITE_BASE_PATH
4. **SPA routing broken**: Fallback configuration issue - check @iamgickpro_fallback

## Impact
- ✅ Assets now load correctly with custom base paths
- ✅ Proper nginx location block handling
- ✅ Normalized environment variable configuration
- ✅ Enhanced debugging and validation tools
- ✅ Better error reporting and troubleshooting

## Files Modified
1. `phases/06-frontend-setup.sh` - Fixed nginx configuration and added validation
2. `phases/04-env-configuration.sh` - Added base path normalization
3. `debug-base-path.sh` - New debugging tool

The fix ensures that IAMGickPro installations with custom base paths work correctly by properly serving assets and handling SPA routing.
