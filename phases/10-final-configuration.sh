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
    
    # Set final file permissions
    print_step "Setting final file permissions"
    
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
    
    print_success "File permissions configured"
    
    # Start background worker service
    print_step "Starting background services"
    
    systemctl start iamgickpro-worker.service
    systemctl status iamgickpro-worker.service --no-pager -l
    
    print_success "Background services started"
    
    # Configure firewall
    print_step "Configuring firewall"
    
    if command -v ufw &> /dev/null; then
        ufw allow OpenSSH
        ufw allow 'Nginx Full'
        ufw --force enable
        print_success "UFW firewall configured"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
        print_success "Firewalld configured"
    else
        print_warning "No firewall detected - please configure manually"
    fi
    
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
    
    # Clear all caches
    php bin/console cache:clear --env=prod
    php bin/console cache:warmup --env=prod
    
    # Optimize composer autoloader
    composer dump-autoload --optimize --no-dev
    
    # Update file locate database
    updatedb &> /dev/null || true
    
    print_success "System optimization completed"
    
    # Generate installation summary
    print_step "Generating installation summary"
    
    cat > /root/iamgickpro-installation-summary.txt << EOF
IAMGickPro Installation Summary
==============================
Installation Date: $(date)
Installation Directory: $INSTALL_DIR
Domain: $DOMAIN_NAME
Frontend URL: $FRONTEND_URL

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

Configuration Files:
- Nginx: /etc/nginx/sites-available/iamgickpro
- Backend Config: $backend_dir/.env

Next Steps:
1. Configure SSL certificates (recommended: certbot --nginx)
2. Set up domain DNS to point to this server
3. Review and customize application settings
4. Consider setting up monitoring and alerting

For support, visit: https://github.com/Webictbyleo/iamgickpro

Installation completed successfully!
EOF

    print_success "Installation summary generated: /root/iamgickpro-installation-summary.txt"
    
   ## rm -rf "$TEMP_DIR"
    apt-get autoremove -y &> /dev/null
    apt-get autoclean &> /dev/null
    
    print_success "Cleanup completed"
    
    print_success "Final configuration completed"
}

# Run the final configuration
final_configuration
