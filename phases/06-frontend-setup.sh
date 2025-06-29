#!/bin/bash

# Phase 6: Frontend Setup 
# Builds and deploys the Vue.js frontend

setup_frontend() {
    print_step "Setting up frontend application"
    
    local frontend_source="$TEMP_DIR/iamgickpro/frontend"
    local webroot="$INSTALL_DIR/public"
    
    # Verify frontend source exists
    if [[ ! -d "$frontend_source" ]]; then
        print_error "Frontend source directory not found: $frontend_source"
        return 1
    fi
    
    # Check if frontend build is needed based on change detection
    if [[ "${FRONTEND_CHANGED:-true}" == "false" ]]; then
        print_step "Frontend unchanged - skipping build and using existing files"
        
        # Verify that existing frontend files are present
        if [[ -f "$webroot/index.html" ]] && [[ -d "$webroot/assets" ]]; then
            print_success "Existing frontend files verified - build skipped"
            
            # Still update the hash cache in case repository was updated
            cd "$frontend_source/.."
            source "$SCRIPT_DIR/phases/03-clone-repository.sh"
            update_frontend_hash
            cd - > /dev/null
            
            return 0
        else
            print_warning "Frontend marked as unchanged but missing files detected - forcing build"
            FRONTEND_CHANGED=true
        fi
    fi
    
    print_step "Frontend changes detected - proceeding with build"
    
    # Install Node.js if not available or wrong version
    print_step "Checking Node.js installation"
    
    if ! command -v node &> /dev/null || [[ "$(node -v | cut -d'v' -f2 | cut -d'.' -f1)" -ne "$NODE_VERSION" ]]; then
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
    
    # Copy frontend source to temporary build location (not install directory)
    print_step "Preparing frontend build"
    
    local frontend_build_dir="$TEMP_DIR/frontend-build"
    
    # Remove existing build directory if it exists
    rm -rf "$frontend_build_dir"
    
    # Copy frontend source to temporary build location
    mkdir -p "$frontend_build_dir"
    cp -r "$frontend_source/"* "$frontend_build_dir/"
    
    cd "$frontend_build_dir"
    
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
    echo "  Package-lock.json exists: $(ls -la package-lock.json 2>/dev/null || echo 'MISSING')"
    
    # Show package.json content for debugging
    echo "  Package.json scripts:"
    if [[ -f "package.json" ]]; then
        cat package.json | grep -A 10 '"scripts"' || echo "    No scripts section found"
    fi
    
    # Install npm dependencies
    print_step "Installing frontend dependencies"
    
    # Clean npm cache to avoid issues
    npm cache clean --force > /dev/null 2>&1 || true
    
    # Capture npm output for debugging
    local npm_log_file="${TEMP_DIR}/npm_install.log"
    
    # Use npm install (includes dev dependencies needed for build)
    print_step "Running npm install..."
    
    # Set a timeout for npm install (10 minutes)
    timeout 600 npm install > "$npm_log_file" 2>&1 &
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
        print_error "NPM install failed (exit code: $npm_exit_code)"
        echo "NPM install output:"
        cat "$npm_log_file"
        return 1
    fi
    
    print_success "Frontend dependencies installed"
    
    # Verify node_modules was created and contains essential packages
    print_step "Validating dependency installation"
    
    if [[ ! -d "node_modules" ]]; then
        print_error "node_modules directory not created"
        return 1
    fi
    
    # Check for key dependencies
    local missing_deps=()
    local key_deps=("vue" "vite" "typescript" "@vitejs/plugin-vue")
    
    for dep in "${key_deps[@]}"; do
        if [[ ! -d "node_modules/$dep" ]]; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_warning "Some key dependencies may be missing: ${missing_deps[*]}"
        echo "  This might cause build issues"
    else
        print_success "Key dependencies verified"
    fi
    
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
    
    # Ensure webroot exists
    mkdir -p "$webroot"
    
    # Copy only the built files from dist to webroot
    if [[ -d "dist" ]] && [[ -n "$(ls -A dist 2>/dev/null)" ]]; then
        cp -r dist/* "$webroot/"
        print_success "Frontend dist files copied to webroot"
    else
        print_error "Frontend dist directory is empty or missing"
        return 1
    fi
    
    # Verify essential frontend files exist in webroot
    if [[ ! -f "$webroot/index.html" ]]; then
        print_error "index.html not found in webroot after deployment"
        return 1
    fi
    
    print_success "Frontend deployed to webroot"
    
    # Set proper permissions on webroot
    print_step "Setting webroot permissions"
    
    # Set proper ownership and permissions
    chown -R www-data:www-data "$webroot"
    chmod -R 755 "$webroot"
    
    print_success "Webroot permissions set"
    
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
    gzip_proxied any;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/javascript application/json;

    # API routes (backend processing)
    location /api/ {
        root $INSTALL_DIR/backend/public;
        try_files \$uri /index.php\$is_args\$args;
    }

    # Handle PHP files in API
    location ~ \.php$ {
        root $INSTALL_DIR/backend/public;
        include snippets/fastcgi-php.conf;
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        
        # Security and timeouts
        fastcgi_hide_header X-Powered-By;
        fastcgi_read_timeout 300s;
        fastcgi_send_timeout 300s;
        fastcgi_connect_timeout 60s;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }

    # Media file routes (serve from backend)
    location /media/ {
       root $INSTALL_DIR/backend/public;
        try_files \$uri /index.php\$is_args\$args;
    }

    # Upload file routes (serve from backend)
    location /uploads/ {
        root $INSTALL_DIR/backend/public;
        try_files \$uri /index.php\$is_args\$args;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Storage file routes (serve from backend)
    location /storage/ {
        root $INSTALL_DIR/backend/public;
        try_files \$uri /index.php\$is_args\$args;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Thumbnail routes (serve from backend)
    location /thumbnails/ {
        root $INSTALL_DIR/backend/public;
        try_files \$uri /index.php\$is_args\$args;
    }

    # Secure media routes (serve from backend with security checks)
    location /secure-media/ {
        root $INSTALL_DIR/backend/public;
        try_files \$uri /index.php\$is_args\$args;
        
    }

    

    # Frontend routes (SPA) - must be last to catch all remaining routes
    location / {
        root /var/www/html/iamgickpro/public;
		index index.html;
        try_files \$uri \$uri/ /index.html;
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
}
EOF

    # Enable the site
    ln -sf /etc/nginx/sites-available/iamgickpro /etc/nginx/sites-enabled/
    
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
    
    # Check for assets directory (common in Vite builds)
    if [[ -d "$webroot/assets" ]]; then
        print_success "Frontend assets directory found"
    else
        print_warning "Frontend validation warning: assets directory not found (may be in different location)"
    fi
    
    # Check for common static files
    local static_files_found=0
    for pattern in "*.js" "*.css" "*.ico"; do
        if ls "$webroot"/$pattern 1> /dev/null 2>&1 || find "$webroot" -name "$pattern" -type f | grep -q .; then
            static_files_found=$((static_files_found + 1))
        fi
    done
    
    if [[ $static_files_found -gt 0 ]]; then
        print_success "Frontend static files validated ($static_files_found types found)"
    else
        print_warning "No common static files (js/css/ico) found in webroot"
    fi
    
    print_success "Frontend setup completed"
    
    # Update frontend hash cache after successful build
    print_step "Updating frontend change detection cache"
    cd "$frontend_source/.."
    source "$SCRIPT_DIR/phases/03-clone-repository.sh"
    update_frontend_hash
    cd - > /dev/null
    
    # Cleanup temporary build directory
    print_step "Cleaning up build files"
   # rm -rf "$frontend_build_dir"
    print_success "Build cleanup completed"
}

# Run the setup
setup_frontend
