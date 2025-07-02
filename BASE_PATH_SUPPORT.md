# IAMGickPro Base Path Support

IAMGickPro now supports installation at custom URL paths, allowing you to host the application in subdirectories like `https://example.com/image-editor/` or `https://store.com/design-tool/`.

## Overview

The base path feature enables:
- **Root Installation**: `https://example.com/` (default behavior)
- **Subdirectory Installation**: `https://example.com/custom-path/`

This is useful when:
- You want to host IAMGickPro alongside other applications
- Your domain serves multiple services
- You need to integrate IAMGickPro into an existing website structure

## Installation Process

### Interactive Configuration

During installation, the installer will prompt you for a base path:

```bash
Base Path Configuration:
Leave empty to install at domain root (https://example.com/)
Or specify a path to install as subdirectory (e.g., /image-editor, /design-tool)

Base path [leave empty for root]: /image-editor
```

### Supported Base Path Formats

- `/image-editor` → `https://example.com/image-editor/`
- `/design-tool` → `https://example.com/design-tool/`
- `/products/editor` → `https://example.com/products/editor/`

**Requirements:**
- Must start with `/`
- Can contain letters, numbers, hyphens, and underscores
- Supports nested paths (e.g., `/products/editor`)
- No trailing slash required (automatically handled)

## Technical Implementation

### Frontend Changes

1. **Vite Configuration**: 
   - Uses `VITE_BASE_PATH` environment variable
   - Sets Vite's `base` option for proper asset handling
   
2. **Vue Router**: 
   - Configures `createWebHistory()` with base path
   - Ensures proper route resolution

3. **Environment Variables**:
   ```bash
   VITE_BASE_PATH=/image-editor
   VITE_API_URL=https://example.com/image-editor/api
   ```

### Backend Changes

1. **Environment Configuration**:
   ```bash
   BASE_PATH=/image-editor
   FRONTEND_URL=https://example.com/image-editor
   BACKEND_URL=https://example.com/image-editor
   ```

2. **CORS Configuration**: 
   - Automatically includes base path in allowed origins

### Nginx Configuration

The installer generates different nginx configurations based on whether a base path is specified:

#### Root Installation (No Base Path)
```nginx
server {
    listen 80;
    server_name example.com;
    root /var/www/html/iamgickpro/public;
    
    location /api/ { ... }
    location / { ... }
}
```

#### Subdirectory Installation (With Base Path)
```nginx
server {
    listen 80;
    server_name example.com;
    
    location /image-editor {
        alias /var/www/html/iamgickpro/public;
        try_files $uri $uri/ @iamgickpro_fallback;
    }
    
    location @iamgickpro_fallback {
        rewrite ^.*$ /image-editor/index.html last;
    }
    
    location /image-editor/api/ {
        rewrite ^/image-editor/api/(.*)$ /api/$1 break;
        root /var/www/html/iamgickpro/backend/public;
        try_files $uri /index.php$is_args$args;
    }
}
```

## URL Structure Examples

### Root Installation
- Application: `https://example.com/`
- API: `https://example.com/api/`
- Media: `https://example.com/media/`
- Uploads: `https://example.com/uploads/`

### Subdirectory Installation (`/image-editor`)
- Application: `https://example.com/image-editor/`
- API: `https://example.com/image-editor/api/`
- Media: `https://example.com/image-editor/media/`
- Uploads: `https://example.com/image-editor/uploads/`

## Configuration Cache

The base path is stored in the installer's configuration cache:

```bash
# View cached configuration (including base path)
sudo ./install.sh --show-cache

# Clear cache to reconfigure base path
sudo ./install.sh --clear-cache
```

## Troubleshooting

### Common Issues

1. **Assets not loading**: Check that `VITE_BASE_PATH` matches your actual base path
2. **API calls failing**: Verify nginx rewrite rules are correct
3. **Router navigation issues**: Ensure Vue Router base path is configured

### Manual Configuration

If you need to change the base path after installation:

1. **Update Frontend Environment**:
   ```bash
   vim /var/www/html/iamgickpro/frontend/.env
   # Update VITE_BASE_PATH and VITE_API_URL
   ```

2. **Update Backend Environment**:
   ```bash
   vim /var/www/html/iamgickpro/backend/.env
   # Update BASE_PATH, FRONTEND_URL, BACKEND_URL
   ```

3. **Update Nginx Configuration**:
   ```bash
   vim /etc/nginx/sites-available/iamgickpro
   # Update location blocks and rewrite rules
   ```

4. **Rebuild Frontend**:
   ```bash
   cd /var/www/html/iamgickpro/frontend
   npm run build
   ```

5. **Restart Services**:
   ```bash
   sudo systemctl reload nginx
   sudo systemctl restart php8.4-fpm
   ```

## Examples of Use Cases

### E-commerce Integration
Host IAMGickPro as a product customization tool:
```
https://store.com/customize/
```

### Multi-tenant Platform
Different design tools for different purposes:
```
https://platform.com/logo-editor/
https://platform.com/banner-editor/
https://platform.com/social-media-editor/
```

### White-label Solutions
Integrate into existing client websites:
```
https://client1.com/design/
https://client2.com/editor/
```

## Security Considerations

- Base paths are validated during installation to prevent path traversal
- Only alphanumeric characters, hyphens, and underscores are allowed
- Nginx configurations include proper security headers regardless of base path
- CORS settings automatically include the full URL with base path

## Performance Notes

- Base path configuration has no performance impact
- Static assets are served efficiently with proper cache headers
- API routing is handled via nginx rewrite rules (minimal overhead)

---

For support or questions about base path configuration, please refer to the main IAMGickPro documentation or contact support.
