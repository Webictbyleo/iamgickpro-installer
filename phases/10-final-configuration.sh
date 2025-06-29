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
    ADMIN_EXISTS=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -se "SELECT COUNT(*) FROM user WHERE email='$ADMIN_EMAIL';")
    
    if [[ $ADMIN_EXISTS -eq 0 ]]; then
        # Create admin user using Symfony console command
        php bin/console app:user:create \
            --email="$ADMIN_EMAIL" \
            --password="$ADMIN_PASSWORD" \
            --role="ROLE_ADMIN" \
            --first-name="Admin" \
            --last-name="User" \
            --env=prod &> /dev/null
        
        if [[ $? -eq 0 ]]; then
            print_success "Admin user created: $ADMIN_EMAIL"
        else
            # Fallback: Create admin user via direct database insertion
            print_step "Creating admin user via database"
            
            # Generate password hash
            HASHED_PASSWORD=$(php -r "echo password_hash('$ADMIN_PASSWORD', PASSWORD_DEFAULT);")
            
            mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << EOF
INSERT INTO user (email, password, roles, first_name, last_name, created_at, updated_at) 
VALUES (
    '$ADMIN_EMAIL',
    '$HASHED_PASSWORD', 
    '["ROLE_ADMIN", "ROLE_USER"]',
    'Admin',
    'User',
    NOW(),
    NOW()
);
EOF
            
            if [[ $? -eq 0 ]]; then
                print_success "Admin user created via database: $ADMIN_EMAIL"
            else
                print_error "Failed to create admin user"
                return 1
            fi
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
    
    # Create system monitoring script
    print_step "Setting up system monitoring"
    
    cat > /usr/local/bin/iamgickpro-status << EOF
#!/bin/bash
# IAMGickPro System Status Script

echo "=== IAMGickPro System Status ==="
echo "Date: \$(date)"
echo

echo "=== Services ==="
systemctl is-active --quiet nginx && echo "✓ Nginx: Running" || echo "✗ Nginx: Stopped"
systemctl is-active --quiet mysql && echo "✓ MySQL: Running" || echo "✗ MySQL: Stopped"
systemctl is-active --quiet php8.4-fpm && echo "✓ PHP-FPM: Running" || echo "✗ PHP-FPM: Stopped"
systemctl is-active --quiet redis-server && echo "✓ Redis: Running" || echo "✗ Redis: Stopped"
systemctl is-active --quiet iamgickpro-worker && echo "✓ Background Worker: Running" || echo "✗ Background Worker: Stopped"
echo

echo "=== Database ==="
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -se "SELECT COUNT(*) AS users FROM user;" 2>/dev/null && echo "✓ Database: Connected" || echo "✗ Database: Connection failed"
echo

echo "=== Disk Usage ==="
df -h "$INSTALL_DIR" | tail -1 | awk '{print "Application: " \$3 " used of " \$2 " (" \$5 " full)"}'
echo

echo "=== Memory Usage ==="
free -h | grep "Mem:" | awk '{print "Memory: " \$3 " used of " \$2}'
echo

echo "=== Web Status ==="
curl -s -o /dev/null -w "HTTP Status: %{http_code}" "http://localhost" 2>/dev/null || echo "Web server: Not responding"
echo
EOF

    chmod +x /usr/local/bin/iamgickpro-status
    
    print_success "System monitoring configured"
    
    # Create maintenance scripts
    print_step "Creating maintenance tools"
    
    # Log rotation script
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
    
    # Create update script
    cat > /usr/local/bin/iamgickpro-update << EOF
#!/bin/bash
# IAMGickPro Update Script

set -e

BACKUP_DIR="/var/backups/iamgickpro/updates"
INSTALL_DIR="$INSTALL_DIR"
TEMP_DIR="/tmp/iamgickpro-update"

echo "=== IAMGickPro Update Script ==="
echo "Starting update process..."

# Create backup
echo "Creating backup..."
mkdir -p "\$BACKUP_DIR"
tar -czf "\$BACKUP_DIR/backup-\$(date +%Y%m%d_%H%M%S).tar.gz" -C "\$INSTALL_DIR" .

# Clone latest version
echo "Downloading latest version..."
rm -rf "\$TEMP_DIR"
git clone https://github.com/Webictbyleo/iamgickpro.git "\$TEMP_DIR"

# Update backend
echo "Updating backend..."
cd "\$INSTALL_DIR/backend"
cp .env.local "\$TEMP_DIR/backend/.env.local"
rsync -av --exclude=var/ --exclude=vendor/ --exclude=.env* "\$TEMP_DIR/backend/" .
composer install --no-dev --optimize-autoloader --no-interaction
php bin/console cache:clear --env=prod
php bin/console doctrine:migrations:migrate --no-interaction --env=prod

# Update frontend
echo "Updating frontend..."
cd "\$TEMP_DIR/frontend"
npm ci --production
npm run build
rsync -av dist/ "\$INSTALL_DIR/public/"

# Restart services
echo "Restarting services..."
systemctl restart php8.4-fpm
systemctl restart nginx
systemctl restart iamgickpro-worker

echo "Update completed successfully!"
EOF

    chmod +x /usr/local/bin/iamgickpro-update
    
    print_success "Update tools created"
    
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

Useful Commands:
- System Status: iamgickpro-status
- Update Application: iamgickpro-update
- Update Content: iamgickpro-update-content
- Backup Database: iamgickpro-backup
- View Logs: tail -f $backend_dir/var/log/prod.log

Configuration Files:
- Nginx: /etc/nginx/sites-available/iamgickpro
- Backend Config: $backend_dir/.env.local

Next Steps:
1. Configure SSL certificates (recommended: certbot --nginx)
2. Set up domain DNS to point to this server
3. Review and customize application settings
4. Consider setting up monitoring and alerting

For support, visit: https://github.com/Webictbyleo/iamgickpro

Installation completed successfully!
EOF

    print_success "Installation summary generated: /root/iamgickpro-installation-summary.txt"
    
    # Cleanup temporary files
    print_step "Cleaning up temporary files"
    
    rm -rf "$TEMP_DIR"
    apt-get autoremove -y &> /dev/null
    apt-get autoclean &> /dev/null
    
    print_success "Cleanup completed"
    
    print_success "Final configuration completed"
}

# Run the final configuration
final_configuration
