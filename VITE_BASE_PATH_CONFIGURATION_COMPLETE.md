# Vite Base Path Configuration - Complete Solution

## Question: Does Vite automatically generate the base tag in index.html?

**Answer: NO** - Vite does NOT automatically inject a `<base>` tag into your HTML file. You need to manually configure this.

## How Vite Handles Base Path

When you set `base: '/my-path/'` in `vite.config.ts`, Vite only:

1. ✅ **Prefixes asset URLs** in built JS/CSS files  
2. ✅ **Adjusts module imports** to use the correct base path
3. ✅ **Updates asset references** in the generated JavaScript
4. ❌ **Does NOT add `<base>` tag** to HTML automatically

## The Problem

Without a `<base>` tag in the HTML:
- ✅ Assets load correctly (JS, CSS files)
- ❌ **Vue Router fails** for subdirectory installations
- ❌ **Relative URLs break** when navigating
- ❌ **Browser history** doesn't work properly

## Complete Solution Implemented

### 1. Updated `index.html` Template

**Before:**
```html
<head>
    <meta charset="UTF-8" />
    <title>%VITE_APP_TITLE% - Design Platform</title>
    <!-- No base tag -->
</head>
```

**After:**
```html
<head>
    <meta charset="UTF-8" />
    <title>%VITE_APP_TITLE% - Design Platform</title>
    <base href="%VITE_BASE_PATH%" />
    <!-- Vite will replace %VITE_BASE_PATH% with actual value -->
</head>
```

### 2. Enhanced `vite.config.ts`

Added custom HTML transformation plugin:

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

### 3. Environment Variable Processing

The installer now sets proper environment variables:

```bash
# In .env file:
VITE_BASE_PATH=/product-1/    # For subdirectory
# OR
VITE_BASE_PATH=/              # For root installation
```

## How It Works

### Build Process
1. **Environment Setup**: Installer creates `.env` with `VITE_BASE_PATH`
2. **Vite Config**: Reads `VITE_BASE_PATH` and sets `base: basePath`
3. **HTML Transform**: Custom plugin replaces `%VITE_BASE_PATH%` in HTML
4. **Asset Processing**: Vite prefixes all asset URLs with base path
5. **Final Output**: Built files have correct base tag and asset paths

### Final Output Examples

**Root Installation (`VITE_BASE_PATH=/`):**
```html
<base href="/" />
<script type="module" src="/assets/index-abc123.js"></script>
```

**Subdirectory Installation (`VITE_BASE_PATH=/product-1/`):**
```html
<base href="/product-1/" />
<script type="module" src="/product-1/assets/index-abc123.js"></script>
```

## Enhanced Validation

### Build-Time Validation
The installer now checks:
- ✅ Environment variables are set correctly
- ✅ Base path is properly formatted (`/path/` with trailing slash)
- ✅ Built HTML contains correct base tag
- ✅ Asset files are generated in correct directory

### Deployment Validation
- ✅ Verifies base tag exists in deployed HTML
- ✅ Tests asset serving through nginx
- ✅ Checks for unprocessed template variables

### Debug Tool Enhancement
- ✅ Detects unprocessed template variables (`%VITE_BASE_PATH%`)
- ✅ Validates base tag configuration
- ✅ Provides specific troubleshooting for template issues

## Common Issues and Solutions

### Issue 1: Base tag shows `%VITE_BASE_PATH%`
**Problem**: Vite didn't process the HTML template  
**Solution**: Check that the custom HTML transform plugin is working

### Issue 2: Assets load but routing breaks
**Problem**: Missing or incorrect base tag  
**Solution**: Verify base tag matches the nginx location path

### Issue 3: Wrong base path format
**Problem**: Base path doesn't end with `/`  
**Solution**: Environment normalization ensures proper format

## Testing the Solution

### 1. Check Environment Variables
```bash
# In frontend build directory
grep VITE_BASE_PATH .env
# Should show: VITE_BASE_PATH=/your-path/
```

### 2. Verify Built HTML
```bash
# Check built index.html
grep -E "(base|href)" /var/www/html/iamgickpro/public/index.html
# Should show: <base href="/your-path/" />
```

### 3. Test Asset Loading
```bash
# Test asset URL
curl -I http://yourdomain.com/your-path/assets/index-*.js
# Should return 200 OK
```

### 4. Test SPA Routing
- Navigate to subdirectory URL: `http://yourdomain.com/your-path/`
- Click internal navigation links
- Refresh page on a sub-route
- All should work correctly

## Key Takeaways

1. **Vite requires manual base tag setup** for proper SPA routing
2. **Template variables** need custom processing in Vite config
3. **Base path format matters** - must end with `/` for proper resolution
4. **Both nginx config AND base tag** are needed for full functionality
5. **Validation at multiple stages** prevents deployment issues

This solution ensures that IAMGickPro works correctly whether installed at the domain root or in a subdirectory, with proper asset loading AND SPA routing functionality.
