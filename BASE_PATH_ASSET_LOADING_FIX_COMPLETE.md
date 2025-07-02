# Base Path Asset Loading Fix - Comprehensive Solution

## Issue Description
After installing IAMGickPro with a custom base path (e.g., `/product-1`), the `<base>` tag in the HTML is correct, but assets (JS, CSS files) are still loading from the root level:
- ❌ **Wrong**: `https://example.com/assets/file.js`
- ✅ **Correct**: `https://example.com/product-1/assets/file.js`

## Root Cause Analysis
The issue occurs because:
1. **Vite base path not applied**: Even though `base: basePath` is set in `vite.config.ts`, the build process may not be reading the environment variable correctly
2. **Missing HTML transform plugin**: The custom plugin to replace `%VITE_BASE_PATH%` wasn't included in the user's manual edits
3. **Environment variable format**: The .env file format or variable reading might have issues

## Complete Solution

### 1. Fixed Vite Configuration (`frontend/vite.config.ts`)

**Added HTML Transform Plugin:**
```typescript
export default defineConfig(({ command, mode }) => {
  const basePath = process.env.VITE_BASE_PATH || '/'
  
  return {
    plugins: [
      vue(),
      // Custom plugin to replace HTML template variables
      {
        name: 'html-transform',
        transformIndexHtml(html) {
          return html
            .replace(/%VITE_BASE_PATH%/g, basePath)
            .replace(/%VITE_APP_TITLE%/g, process.env.VITE_APP_TITLE || 'IAMGickPro')
        }
      }
    ],
    base: basePath,
    // ... rest of config
  }
})
```

### 2. Enhanced Environment Configuration Debug (`phases/04-env-configuration.sh`)

**Added debugging output:**
```bash
# Debug the generated frontend .env file
print_step "Frontend .env file content:"
echo "  VITE_BASE_PATH value: $(grep '^VITE_BASE_PATH=' "$frontend_env" | cut -d'=' -f2)"
echo "  Raw BASE_PATH: '$BASE_PATH'"
echo "  Processed vite_base_path: '$vite_base_path'"
```

### 3. Enhanced Build Process Debug (`phases/06-frontend-setup.sh`)

**Added comprehensive debugging:**
```bash
# Show build environment
print_step "Build environment variables:"
echo "  NODE_ENV: $NODE_ENV"
if [[ -f ".env" ]]; then
    echo "  VITE_BASE_PATH from .env: $(grep '^VITE_BASE_PATH=' .env | cut -d'=' -f2)"
fi

# Enhanced asset validation
echo "Asset references in index.html:"
if [[ -n "$BASE_PATH" && "$BASE_PATH" != "/" ]]; then
    if grep -o 'src="[^"]*assets/[^"]*"' "dist/index.html" | head -3; then
        echo "  Checking if assets use base path..."
        if grep -q "src=\"$BASE_PATH" "dist/index.html"; then
            print_success "Assets appear to use correct base path"
        else
            print_warning "Assets may not be using base path"
            grep -o 'src="[^"]*"' "dist/index.html" | head -3
        fi
    fi
fi
```

### 4. Created Test Script (`test-base-path-assets.sh`)

A comprehensive testing tool that:
- Analyzes the built index.html for correct asset paths
- Tests actual asset URLs via HTTP requests
- Compares expected vs actual asset URLs
- Provides specific diagnostic information
- Offers troubleshooting recommendations

## How to Use the Fix

### For New Installations
The enhanced installer will automatically:
1. Set correct environment variables
2. Apply the HTML transform plugin
3. Validate asset paths during build
4. Test asset serving after deployment

### For Existing Installations
1. **Update Vite config** (add HTML transform plugin)
2. **Rebuild frontend:**
   ```bash
   cd /path/to/frontend
   npm run build
   ```
3. **Test with debug script:**
   ```bash
   sudo ./test-base-path-assets.sh [INSTALL_DIR] [DOMAIN]
   ```

## Debugging Workflow

### Step 1: Check Environment Variables
```bash
# In frontend directory
grep VITE_BASE_PATH .env
# Should show: VITE_BASE_PATH=/your-path/
```

### Step 2: Check Built HTML
```bash
# Check base tag
grep -E '<base[^>]*>' /path/to/webroot/index.html
# Should show: <base href="/your-path/" />

# Check asset sources
grep -oE 'src="[^"]*"' /path/to/webroot/index.html | head -5
# Should show: src="/your-path/assets/..."
```

### Step 3: Test Asset URLs
```bash
# Test asset access
curl -I http://yourdomain.com/your-path/assets/index-*.js
# Should return: HTTP/1.1 200 OK
```

### Step 4: Use Test Script
```bash
sudo ./test-base-path-assets.sh
```

## Common Issues and Solutions

### Issue 1: Assets still load from root
**Symptom**: `src="/assets/file.js"` instead of `src="/base-path/assets/file.js"`
**Cause**: Vite not reading VITE_BASE_PATH correctly
**Solution**: 
1. Check .env file format
2. Ensure HTML transform plugin is active
3. Rebuild with `NODE_ENV=production npm run build`

### Issue 2: Base tag correct but assets 404
**Symptom**: `<base href="/base-path/">` is correct but assets return 404
**Cause**: Nginx configuration issue
**Solution**: Verify nginx location blocks for assets

### Issue 3: Environment variable not set
**Symptom**: VITE_BASE_PATH is empty or undefined
**Cause**: Environment configuration phase failed
**Solution**: Re-run phase 04 (environment configuration)

## Technical Details

### Vite Base Path Behavior
When `base: '/my-path/'` is set in Vite config:
1. ✅ **Import statements** in JS get prefixed: `import('/my-path/assets/chunk.js')`
2. ✅ **Asset URLs** in CSS get prefixed: `url(/my-path/assets/image.png)`
3. ✅ **Script/link tags** in HTML get prefixed: `src="/my-path/assets/index.js"`
4. ❌ **Base tag** is NOT automatically added (must be manual)

### Environment Variable Processing
The installer processes base paths as follows:
1. **Input**: User provides base path (e.g., `product-1`)
2. **Normalization**: Add leading slash, remove trailing slash (`/product-1`)
3. **Vite Format**: Add trailing slash for Vite (`/product-1/`)
4. **Output**: Assets prefixed correctly (`/product-1/assets/...`)

### Nginx Location Matching
For subdirectory installations, nginx needs specific location blocks:
```nginx
# Assets with base path
location ~ ^/product-1/assets/(.*)$ {
    root /webroot;
    try_files /assets/$1 =404;
}

# Main application
location /product-1 {
    root /webroot;
    try_files $uri $uri/ @fallback;
}
```

## Validation Checklist

After applying the fix:
- [ ] VITE_BASE_PATH set correctly in frontend/.env
- [ ] HTML transform plugin added to vite.config.ts
- [ ] Built index.html has correct base tag
- [ ] Built index.html assets use base path prefix
- [ ] Asset URLs return 200 OK via HTTP test
- [ ] SPA routing works correctly
- [ ] Browser network tab shows assets loading from correct URLs

## Files Modified
1. `frontend/vite.config.ts` - Added HTML transform plugin
2. `phases/04-env-configuration.sh` - Enhanced debug output
3. `phases/06-frontend-setup.sh` - Enhanced build validation
4. `test-base-path-assets.sh` - New comprehensive testing tool

This fix ensures that Vite correctly applies the base path to all asset URLs during the build process, resolving the issue where assets load from the root level instead of the configured base path.
