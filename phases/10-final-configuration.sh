#!/bin/bash

# Phase 10: Final Configuration
# Creates admin account, finalizes permissions, and completes setup

final_configuration() {
    print_step "Performing final configuration"
    
    local backend_dir="$INSTALL_DIR/backend"
    
    cd "$backend_dir"
    
    # Create admin user account
    print_step "Creating admin user account"
    
    # Check if admin user already exists
    ADMIN_EXISTS=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -se "SELECT COUNT(*) FROM users WHERE email='$ADMIN_EMAIL';")
    
    if [[ $ADMIN_EXISTS -eq 0 ]]; then
        # Create admin user using the correct admin creation command
        print_step "Creating admin user: $ADMIN_EMAIL"
        
        php bin/console app:create-admin \
            --email="$ADMIN_EMAIL" \
            --password="$ADMIN_PASSWORD" \
            --first-name="$ADMIN_FIRST_NAME" \
            --last-name="$ADMIN_LAST_NAME" \
            --username="admin" \
            --env=prod
        
        if [[ $? -eq 0 ]]; then
            print_success "Admin user created: $ADMIN_EMAIL"
        else
            print_error "Failed to create admin user"
            return 1
        fi
    else
        print_success "Admin user already exists: $ADMIN_EMAIL"
    fi
    
    # Set initial file permissions
    print_step "Setting initial file permissions"
    
    # Backend permissions
    chown -R www-data:www-data "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    
    # Specific permission requirements
    chmod -R 775 "$backend_dir/var"
    chmod -R 775 "$backend_dir/public/uploads"
    chmod -R 775 "$backend_dir/storage"
    chmod 600 "$backend_dir/config/jwt/private.pem"
    chmod 644 "$backend_dir/config/jwt/public.pem"
    
    # Frontend webroot permissions
    chmod -R 755 "$INSTALL_DIR/public"
    
    print_success "Initial file permissions configured"
    
    # Ensure cache permissions are correct and refresh if needed
    print_step "Configuring production cache"
    
    # Clear any existing cache to prevent corruption
    print_step "Clearing all existing cache"
    rm -rf "$backend_dir/var/cache" || true
    
    # Ensure proper ownership of var directory
    chown -R www-data:www-data "$backend_dir/var"
    chmod -R 775 "$backend_dir/var"
    
    # Regenerate cache with proper ownership
    print_step "Regenerating production cache"
    sudo -u www-data php bin/console cache:clear --env=prod --no-warmup
    sudo -u www-data php bin/console cache:warmup --env=prod
    
    # Verify cache was created successfully
    if [[ ! -d "$backend_dir/var/cache/prod" ]]; then
        print_error "Failed to create production cache"
        return 1
    fi
    
    # Ensure correct permissions on generated cache
    chown -R www-data:www-data "$backend_dir/var/cache"
    chmod -R 775 "$backend_dir/var/cache"
    
    # Final composer optimization
    composer dump-autoload --optimize --no-dev
    
    # Additional cache validation - try to instantiate key services
    print_step "Validating cache integrity"
    sudo -u www-data php bin/console debug:container --env=prod LayerController > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        print_warning "Cache validation failed, regenerating..."
        rm -rf "$backend_dir/var/cache/prod"
        sudo -u www-data php bin/console cache:clear --env=prod --no-warmup
        sudo -u www-data php bin/console cache:warmup --env=prod
        chown -R www-data:www-data "$backend_dir/var/cache"
        chmod -R 775 "$backend_dir/var/cache"
    fi
    
    print_success "Production cache configured and validated"
    
    # Start background worker service
    print_step "Starting background services"
    
    systemctl start iamgickpro-worker.service
    systemctl status iamgickpro-worker.service --no-pager -l
    
    print_success "Background services started"
   
    
    
    # Create log rotation configuration
    print_step "Configuring log rotation"
    
    cat > /etc/logrotate.d/iamgickpro << EOF
$backend_dir/var/log/*.log {
    daily
    missingok
    rotate 14
    compress
    notifempty
    create 0644 www-data www-data
    postrotate
        systemctl reload php8.4-fpm
    endscript
}

/var/log/php/iamgickpro-errors.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    create 0644 www-data www-data
}
EOF

    print_success "Log rotation configured"
    
    # Run final system optimization
    print_step "Running system optimization"
    
    # Update file locate database
    updatedb &> /dev/null || true
    
    print_success "System optimization completed"
    
    # Setup SSL with Let's Encrypt
    print_step "Setting up SSL with Let's Encrypt"
    
    # Check if domain is accessible (skip SSL if localhost or IP)
    if [[ "$DOMAIN_NAME" == "localhost" ]] || [[ "$DOMAIN_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_warning "Skipping SSL setup - domain is localhost or IP address"
        print_warning "SSL is only available for proper domain names"
        SSL_CONFIGURED="No (localhost/IP)"
    else
        # Install certbot if not present
        if ! command -v certbot &> /dev/null; then
            print_step "Installing Certbot for Let's Encrypt"
            
            # Install snapd if not present
            if ! command -v snap &> /dev/null; then
                apt update
                apt install -y snapd
                systemctl enable snapd
                systemctl start snapd
                
                # Wait for snapd to be ready
                sleep 5
            fi
            
            # Install certbot via snap (recommended method)
            snap install core; snap refresh core
            snap install --classic certbot
            
            # Create symlink
            ln -sf /snap/bin/certbot /usr/bin/certbot
            
            if ! command -v certbot &> /dev/null; then
                print_error "Failed to install Certbot"
                print_warning "SSL setup skipped - continuing without HTTPS"
                SSL_CONFIGURED="No (certbot installation failed)"
            else
                print_success "Certbot installed successfully"
            fi
        else
            print_success "Certbot already installed"
        fi
        
        # Attempt to obtain SSL certificate and configure nginx automatically
        if command -v certbot &> /dev/null; then
            print_step "Setting up SSL certificate for $DOMAIN_NAME"
            
            # Use certbot nginx plugin - it handles existing certificates automatically
            if certbot --nginx --non-interactive --agree-tos --redirect --email "admin@$DOMAIN_NAME" -d "$DOMAIN_NAME"; then
                print_success "SSL certificate configured successfully"
                print_success "Site is now available at https://$DOMAIN_NAME with automatic HTTP to HTTPS redirect"
                SSL_CONFIGURED="Yes (https://$DOMAIN_NAME)"
                
                # Setup automatic certificate renewal if not already configured
                if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
                    print_step "Setting up automatic certificate renewal"
                    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
                    print_success "Automatic certificate renewal configured"
                fi
            else
                print_warning "SSL setup failed - continuing with HTTP"
                print_warning "Common causes:"
                print_warning "  - Domain $DOMAIN_NAME does not point to this server"
                print_warning "  - Port 80/443 not accessible from the internet"
                print_warning "  - Firewall blocking connections"
                print_warning "Site remains available at http://$DOMAIN_NAME"
                SSL_CONFIGURED="No (certificate setup failed)"
            fi
        else
            SSL_CONFIGURED="No (certbot not available)"
        fi
    fi
    
    # Generate installation summary
    print_step "Generating installation summary"
    
    cat > /root/iamgickpro-installation-summary.txt << EOF
IAMGickPro Installation Summary
==============================
Installation Date: $(date)
Installation Directory: $INSTALL_DIR
Domain: $DOMAIN_NAME
Frontend URL: $FRONTEND_URL
SSL Certificate: ${SSL_CONFIGURED:-"Not configured"}

Database Configuration:
- Host: $DB_HOST:$DB_PORT
- Database: $DB_NAME
- User: $DB_USER

Admin Account:
- Email: $ADMIN_EMAIL
- Password: $ADMIN_PASSWORD

System Information:
- OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
- PHP Version: $(php -v | head -n1)
- Node.js Version: $(node -v)
- Nginx Version: $(nginx -v 2>&1)
- MySQL Version: $(mysql --version)

Installed Components:
✓ Nginx Web Server
✓ MySQL Database
✓ PHP 8.4 with Extensions
✓ Node.js $NODE_VERSION
✓ Redis Server
✓ ImageMagick (compiled from source)
✓ FFmpeg (compiled from source)
✓ IAMGickPro Application
✓ Background Worker Service
$([ "$SSL_CONFIGURED" != "No"* ] && echo "✓ SSL/TLS Certificate" || echo "⚠ SSL/TLS Certificate (not configured)")

Configuration Files:
- Nginx: /etc/nginx/sites-available/iamgickpro
- Backend Config: $backend_dir/.env

Cache Troubleshooting:
If you encounter cache-related errors (500 errors, missing service files):
1. Clear production cache: sudo -u www-data php bin/console cache:clear --env=prod
2. Regenerate cache: sudo -u www-data php bin/console cache:warmup --env=prod
3. Fix permissions: chown -R www-data:www-data $backend_dir/var && chmod -R 775 $backend_dir/var
4. Validate services: sudo -u www-data php bin/console debug:container --env=prod

Next Steps:
$([ "$SSL_CONFIGURED" == "No"* ] && echo "1. Configure SSL certificates: certbot --nginx -d $DOMAIN_NAME" || echo "1. SSL is configured and ready")
2. Set up domain DNS to point to this server (if not done already)
3. Review and customize application settings
4. Consider setting up monitoring and alerting

For support, visit: https://github.com/Webictbyleo/iamgickpro

Installation completed successfully!
EOF

    print_success "Installation summary generated: /root/iamgickpro-installation-summary.txt"
    
    rm -rf "$TEMP_DIR"
    apt-get autoremove -y &> /dev/null
    apt-get autoclean &> /dev/null
    
    print_success "Cleanup completed"
    
    print_success "Final configuration completed"
}

# Run the final configuration
final_configuration
