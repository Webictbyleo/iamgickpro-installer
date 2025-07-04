#!/bin/bash

# Phase 5: Backend Setup
# Installs and configures the Symfony backend

setup_backend() {
    print_step "Setting up backend application"
    
    local backend_source="$TEMP_DIR/iamgickpro/backend"
    local backend_dest="$INSTALL_DIR/backend"
    
    # Copy backend files to installation directory
    print_step "Copying backend files"
    
    if [[ ! -d "$backend_source" ]]; then
        print_error "Backend source directory not found: $backend_source"
        return 1
    fi
    
    # Create backend directory
    mkdir -p "$backend_dest"
    
    # Copy all backend files except specific directories
    rsync -av --exclude=vendor/ --exclude=var/ --exclude=.env* "$backend_source/" "$backend_dest/"
    
    # Copy the installer-generated .env file
    if [[ -f "$backend_source/.env" ]]; then
        cp "$backend_source/.env" "$backend_dest/.env"
        print_success "Environment configuration copied"
    else
        print_error "Generated .env file not found in $backend_source/.env"
        return 1
    fi
    
    print_success "Backend files copied"
    
    # Set proper ownership and permissions
    print_step "Setting file permissions"
    
    chown -R www-data:www-data "$backend_dest"
    chmod -R 755 "$backend_dest"
    chmod -R 775 "$backend_dest/var" 2>/dev/null || true
    chmod -R 775 "$backend_dest/public/uploads" 2>/dev/null || mkdir -p "$backend_dest/public/uploads" && chmod -R 775 "$backend_dest/public/uploads"
    
    print_success "File permissions set"
    
    # Install Composer dependencies
    print_step "Installing PHP dependencies"
    
    cd "$backend_dest"
    
    # Install Composer if not available
    if ! command -v composer &> /dev/null; then
        print_step "Installing Composer"
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi
    
    # Install dependencies with production optimization
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction --quiet &
    spinner
    wait $!
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to install Composer dependencies"
        return 1
    fi
    
    print_success "PHP dependencies installed"
    
    # Generate JWT keys
    print_step "Generating JWT keys"
    
    mkdir -p config/jwt
    
    # Extract JWT passphrase from .env file more safely
    JWT_PASSPHRASE=$(grep "^JWT_PASSPHRASE=" .env | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    if [[ -z "$JWT_PASSPHRASE" ]]; then
        print_error "JWT_PASSPHRASE not found in .env file"
        return 1
    fi
    
    print_step "Using JWT passphrase from environment configuration"
    
    # Generate private key
    openssl genpkey -algorithm RSA -out config/jwt/private.pem -aes256 -pass pass:"$JWT_PASSPHRASE" -pkeyopt rsa_keygen_bits:4096
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to generate JWT private key"
        return 1
    fi
    
    # Generate public key  
    openssl pkey -in config/jwt/private.pem -out config/jwt/public.pem -pubout -passin pass:"$JWT_PASSPHRASE"
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to generate JWT public key"
        return 1
    fi
    
    # Verify the keys were created successfully
    if [[ ! -f "config/jwt/private.pem" ]] || [[ ! -f "config/jwt/public.pem" ]]; then
        print_error "JWT key files were not created successfully"
        return 1
    fi
    
    # Set JWT key permissions
    chmod 600 config/jwt/private.pem
    chmod 644 config/jwt/public.pem
    chown www-data:www-data config/jwt/*.pem
    
    # Verify JWT configuration with Symfony
    print_step "Verifying JWT configuration"
    
    # Test JWT key loading with a simple Symfony command
    php bin/console debug:config lexik_jwt_authentication &> /dev/null
    if [[ $? -ne 0 ]]; then
        print_warning "JWT configuration test failed, but continuing installation"
        print_warning "You may need to regenerate JWT keys after installation"
    else
        print_success "JWT configuration verified"
    fi
    
    print_success "JWT keys generated and configured"
    
    # Create required directories first
    print_step "Creating required directories"
    
    mkdir -p var/log
    mkdir -p var/cache
    mkdir -p public/uploads/templates
    mkdir -p public/uploads/designs
    mkdir -p public/uploads/media
    mkdir -p storage/shapes
    
    # Set proper permissions for runtime directories BEFORE cache operations
    chown -R www-data:www-data var/
    chown -R www-data:www-data public/uploads/
    chown -R www-data:www-data storage/
    chmod -R 775 var/
    chmod -R 775 public/uploads/
    chmod -R 775 storage/
    
    
    print_success "Required directories created and permissions set"
    
    # Validate backend setup
    print_step "Validating backend installation"
    
    if [[ ! -f "composer.json" ]]; then
        print_error "Backend installation validation failed: composer.json not found"
        return 1
    fi
    
    if [[ ! -f ".env" ]]; then
        print_error "Backend installation validation failed: .env not found"
        return 1
    fi
    
    if [[ ! -d "vendor" ]]; then
        print_error "Backend installation validation failed: vendor directory not found"
        return 1
    fi
    
    if [[ ! -f "config/jwt/private.pem" ]]; then
        print_error "Backend installation validation failed: JWT private key not found"
        return 1
    fi
    
    # Test autoloader
    php -r "require 'vendor/autoload.php'; echo 'Autoloader OK';" &> /dev/null
    if [[ $? -ne 0 ]]; then
        print_error "Backend installation validation failed: autoloader test failed"
        return 1
    fi
    
    print_success "Backend installation validated"
    
    # Create systemd service for async workers (optional)
    print_step "Setting up background workers"
    
    cat > /etc/systemd/system/iamgickpro-worker.service << EOF
[Unit]
Description=IAMGickPro Background Worker
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=$backend_dest
ExecStart=/usr/bin/php $backend_dest/bin/console messenger:consume async --time-limit=3600
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable iamgickpro-worker.service
    
    print_success "Background worker service configured"
    
    print_success "Backend setup completed"
}

# Run the setup
setup_backend
