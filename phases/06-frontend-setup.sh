#!/bin/bash

# Phase 6: Frontend Setup 
# Builds and deploys the Vue.js frontend

setup_frontend() {
    print_step "Setting up frontend application"
    
    local frontend_source="$TEMP_DIR/iamgickpro/frontend"
    local frontend_dest="$INSTALL_DIR/frontend"
    local webroot="$INSTALL_DIR/public"
    
    # Verify frontend source exists
    if [[ ! -d "$frontend_source" ]]; then
        print_error "Frontend source directory not found: $frontend_source"
        return 1
    fi
    
    # Install Node.js if not available or wrong version
    print_step "Checking Node.js installation"
    
    if ! command -v node &> /dev/null || [[ "$(node -v | cut -d'v' -f2 | cut -d'.' -f1)" -lt 18 ]]; then
        print_step "Installing Node.js $NODE_VERSION"
        
        # Install Node.js using NodeSource repository
        curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
        apt-get install -y nodejs
        
        # Verify installation
        if ! command -v node &> /dev/null; then
            print_error "Failed to install Node.js"
            return 1
        fi
        
        print_success "Node.js $(node -v) installed"
    else
        print_success "Node.js $(node -v) already available"
    fi
    
    # Copy frontend source to temporary build location  
    print_step "Preparing frontend build"
    
    mkdir -p "$frontend_dest"
    cp -r "$frontend_source/"* "$frontend_dest/"
    
    cd "$frontend_dest"
    
    # Verify package.json exists
    if [[ ! -f "package.json" ]]; then
        print_error "package.json not found in frontend directory"
        return 1
    fi
    
    # Show npm and node versions for debugging
    print_step "Environment information:"
    echo "  Node.js: $(node -v)"
    echo "  NPM: $(npm -v)"
    echo "  Working directory: $(pwd)"
    echo "  Package.json exists: $(ls -la package.json 2>/dev/null || echo 'MISSING')"
    
    # Install npm dependencies
    print_step "Installing frontend dependencies"
    
    # Clean npm cache to avoid issues
    npm cache clean --force > /dev/null 2>&1 || true
    
    # Capture npm output for debugging
    local npm_log_file="${TEMP_DIR}/npm_install.log"
    
    # Try npm ci first (faster and more reliable for production)
    print_step "Running npm ci --production..."
    
    # Set a timeout for npm install (10 minutes)
    timeout 600 npm ci --production > "$npm_log_file" 2>&1 &
    local npm_pid=$!
    spinner
    wait $npm_pid
    local npm_exit_code=$?
    
    if [[ $npm_exit_code -eq 124 ]]; then
        print_error "NPM install timed out after 10 minutes"
        echo "Last 50 lines of NPM output:"
        tail -n 50 "$npm_log_file" 2>/dev/null || echo "No output file found"
        return 1
    elif [[ $npm_exit_code -ne 0 ]]; then
        print_warning "npm ci failed, trying npm install as fallback"
        echo "npm ci output:"
        cat "$npm_log_file"
        
        # Fallback to npm install
        print_step "Running npm install --production..."
        timeout 600 npm install --production > "$npm_log_file" 2>&1 &
        local npm_pid2=$!
        spinner
        wait $npm_pid2
        local npm_exit_code2=$?
        
        if [[ $npm_exit_code2 -eq 124 ]]; then
            print_error "NPM install fallback timed out after 10 minutes"
            echo "Last 50 lines of NPM output:"
            tail -n 50 "$npm_log_file" 2>/dev/null || echo "No output file found"
            return 1
        elif [[ $npm_exit_code2 -ne 0 ]]; then
            print_error "Both npm ci and npm install failed (exit code: $npm_exit_code2)"
            echo "npm install output:"
            cat "$npm_log_file"
            return 1
        fi
    fi
    
    print_success "Frontend dependencies installed"
    
    # Build frontend for production
    print_step "Building frontend application"
    
    # Capture build output for debugging
    local build_log_file="${TEMP_DIR}/npm_build.log"
    
    # Set a timeout for npm build (15 minutes)
    timeout 900 npm run build > "$build_log_file" 2>&1 &
    local build_pid=$!
    spinner
    wait $build_pid
    local build_exit_code=$?
    
    if [[ $build_exit_code -eq 124 ]]; then
        print_error "NPM build timed out after 15 minutes"
        echo "Last 50 lines of build output:"
        tail -n 50 "$build_log_file" 2>/dev/null || echo "No output file found"
        return 1
    elif [[ $build_exit_code -ne 0 ]]; then
        print_error "Frontend build failed (exit code: $build_exit_code)"
        echo "Build output:"
        cat "$build_log_file"
        return 1
    fi
    
    if [[ ! -d "dist" ]]; then
        print_error "Frontend build failed: dist directory not created"
        return 1
    fi
    
    print_success "Frontend built successfully"
    
    # Deploy built files to webroot
    print_step "Deploying frontend to webroot"
    
    mkdir -p "$webroot"
    
    # Copy built files to webroot
    cp -r dist/* "$webroot/"
    
    # Create necessary subdirectories in webroot
    mkdir -p "$webroot/api"
    mkdir -p "$webroot/uploads"
    
    # Set proper permissions
    chown -R www-data:www-data "$webroot"
    chmod -R 755 "$webroot"
    
    print_success "Frontend deployed to webroot"
    
    # Create nginx configuration
    print_step "Configuring nginx"
    
    cat > "/etc/nginx/sites-available/iamgickpro" << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;
    root $webroot;
    index index.html;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private must-revalidate auth;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/javascript application/json;

    # API routes (proxy to backend)
    location /api/ {
        try_files \$uri @backend;
    }

    # Backend PHP processing
    location @backend {
        root $INSTALL_DIR/backend/public;
        try_files \$uri /index.php\$is_args\$args;
    }

    # PHP-FPM processing for API endpoints
    location ~ ^/api/.*\.php$ {
        root $INSTALL_DIR/backend/public;
        fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTPS off;
    }

    # Media file routes (serve from backend)
    location /media/ {
        alias $INSTALL_DIR/backend/public/media/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri @backend;
    }

    # Upload file routes (serve from backend)
    location /uploads/ {
        alias $INSTALL_DIR/backend/public/uploads/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri @backend;
    }

    # Storage file routes (serve from backend)
    location /storage/ {
        alias $INSTALL_DIR/backend/public/storage/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri @backend;
    }

    # Thumbnail routes (serve from backend)
    location /thumbnails/ {
        alias $INSTALL_DIR/backend/public/thumbnails/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri @backend;
    }

    # Secure media routes (serve from backend)
    location /secure-media/ {
        # This should go through backend for security checks
        try_files \$uri @backend;
    }

    # Frontend routes (SPA) - must be last to catch all remaining routes
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Static assets caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Security: deny access to sensitive files
    location ~ /\. {
        deny all;
    }

    location ~ composer\.(json|lock) {
        deny all;
    }

    location ~ package(-lock)?\.json {
        deny all;
    }

    # File upload limits
    client_max_body_size 50M;
    client_body_timeout 120s;
}
EOF

    # Enable the site
    ln -sf /etc/nginx/sites-available/iamgickpro /etc/nginx/sites-enabled/
    
    # Remove default nginx site if it exists
    rm -f /etc/nginx/sites-enabled/default
    
    # Test nginx configuration
    nginx -t
    if [[ $? -ne 0 ]]; then
        print_error "Nginx configuration test failed"
        return 1
    fi
    
    # Restart nginx
    systemctl restart nginx
    if [[ $? -ne 0 ]]; then
        print_error "Failed to restart nginx"
        return 1
    fi
    
    print_success "Nginx configured and restarted"
    
    # Validate frontend deployment
    print_step "Validating frontend deployment"
    
    if [[ ! -f "$webroot/index.html" ]]; then
        print_error "Frontend validation failed: index.html not found"
        return 1
    fi
    
    if [[ ! -d "$webroot/assets" ]]; then
        print_warning "Frontend validation warning: assets directory not found"
    fi
    
    # Test if site is accessible
    sleep 2
    curl -s -o /dev/null -w "%{http_code}" "http://localhost" | grep -q "200"
    if [[ $? -ne 0 ]]; then
        print_warning "Frontend accessibility test failed - site may not be immediately available"
    else
        print_success "Frontend is accessible"
    fi
    
    print_success "Frontend setup completed"
    
    # Cleanup build directory
    print_step "Cleaning up build files"
    rm -rf "$frontend_dest"
    print_success "Build cleanup completed"
}

# Run the setup
setup_frontend
