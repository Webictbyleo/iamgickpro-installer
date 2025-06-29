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
    
    # Check if frontend needs rebuilding using Git
    local needs_rebuild=false
    local webroot_index="$webroot/index.html"
    local git_hash_file="$webroot/.git-hash"
    
    if [[ ! -f "$webroot_index" ]]; then
        print_step "Frontend not deployed yet, build required"
        needs_rebuild=true
    elif [[ ! -d "$frontend_source/.git" ]]; then
        print_step "Not a git repository, performing build to be safe"
        needs_rebuild=true
    else
        # Get current git hash of frontend directory
        cd "$frontend_source"
        local current_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        local frontend_files_hash=$(git log -1 --format="%H" --name-only . 2>/dev/null | head -1 || echo "unknown")
        
        if [[ ! -f "$git_hash_file" ]]; then
            print_step "No previous build hash found, build required"
            needs_rebuild=true
        else
            local previous_hash=$(cat "$git_hash_file" 2>/dev/null || echo "")
            
            if [[ "$frontend_files_hash" != "$previous_hash" ]]; then
                print_step "Frontend files have changed since last build (hash: ${frontend_files_hash:0:8}), rebuild required"
                needs_rebuild=true
            else
                print_success "Frontend is up to date (hash: ${frontend_files_hash:0:8}), skipping build"
                needs_rebuild=false
            fi
        fi
    fi
    
    if [[ "$needs_rebuild" == "false" ]]; then
        print_success "Frontend build skipped - no changes detected"
        
        # Still need to configure nginx and set permissions
        print_step "Ensuring nginx configuration is current"
        # Jump to nginx configuration section
        configure_nginx_and_permissions
        return 0
    fi
    
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
    
    # Check if npm install is needed using Git
    local needs_npm_install=false
    local node_modules_hash_file="$frontend_build_dir/.npm-install-hash"
    
    if [[ ! -d "node_modules" ]]; then
        print_step "node_modules not found, npm install required"
        needs_npm_install=true
    else
        # Get hash of package.json and package-lock.json
        local package_files_hash=""
        if [[ -f "package.json" ]]; then
            package_files_hash=$(git hash-object package.json 2>/dev/null || echo "no-git")
        fi
        if [[ -f "package-lock.json" ]]; then
            local lock_hash=$(git hash-object package-lock.json 2>/dev/null || echo "no-git")
            package_files_hash="${package_files_hash}-${lock_hash}"
        fi
        
        if [[ ! -f "$node_modules_hash_file" ]]; then
            print_step "No previous npm install hash found, npm install required"
            needs_npm_install=true
        else
            local previous_package_hash=$(cat "$node_modules_hash_file" 2>/dev/null || echo "")
            
            if [[ "$package_files_hash" != "$previous_package_hash" ]]; then
                print_step "package.json or package-lock.json has changed, npm install required"
                needs_npm_install=true
            else
                print_success "Dependencies are up to date, skipping npm install"
                needs_npm_install=false
            fi
        fi
    fi
    
    if [[ "$needs_npm_install" == "true" ]]; then
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
        
        # Save the package files hash for future checks
        local package_files_hash=""
        if [[ -f "package.json" ]]; then
            package_files_hash=$(git hash-object package.json 2>/dev/null || echo "no-git")
        fi
        if [[ -f "package-lock.json" ]]; then
            local lock_hash=$(git hash-object package-lock.json 2>/dev/null || echo "no-git")
            package_files_hash="${package_files_hash}-${lock_hash}"
        fi
        echo "$package_files_hash" > "$node_modules_hash_file"
    fi
    
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
    
    # Save the git hash for future builds
    cd "$frontend_source"
    local frontend_files_hash=$(git log -1 --format="%H" --name-only . 2>/dev/null | head -1 || echo "unknown")
    echo "$frontend_files_hash" > "$webroot/.git-hash"
    
    # Configure nginx and set permissions
    configure_nginx_and_permissions
    
    print_success "Frontend setup completed"
    
    # Cleanup temporary build directory
    print_step "Cleaning up build files"
    rm -rf "$frontend_build_dir"
    print_success "Build cleanup completed"
}

# Configure nginx and set permissions (extracted as separate function)
configure_nginx_and_permissions() {
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
        
        # Handle PHP files in API
        location ~ \.php$ {
            fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
            fastcgi_index index.php;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_param HTTPS off;
        }
    }

    # Media file routes (serve from backend)
    location /media/ {
        alias $INSTALL_DIR/backend/public/media/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    # Upload file routes (serve from backend)
    location /uploads/ {
        alias $INSTALL_DIR/backend/public/uploads/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    # Storage file routes (serve from backend)
    location /storage/ {
        alias $INSTALL_DIR/backend/public/storage/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    # Thumbnail routes (serve from backend)
    location /thumbnails/ {
        alias $INSTALL_DIR/backend/public/thumbnails/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    # Secure media routes (serve from backend with security checks)
    location /secure-media/ {
        root $INSTALL_DIR/backend/public;
        try_files \$uri /index.php\$is_args\$args;
        
        # Handle PHP files for security checks
        location ~ \.php$ {
            fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
            fastcgi_index index.php;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_param HTTPS off;
        }
    }

    # Static assets caching (must be before frontend routes)
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    # Frontend routes (SPA) - must be last to catch all remaining routes
    location / {
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

    # File upload limits
    client_max_body_size 50M;
    client_body_timeout 120s;
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
}

# Run the setup
setup_frontend
