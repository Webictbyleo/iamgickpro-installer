#!/bin/bash

# Phase 7: Database Setup
# Creates database, runs migrations, and verifies setup

setup_database() {
    print_step "Setting up database"
    
    local backend_dir="$INSTALL_DIR/backend"
    
    # Determine which credentials to use for database operations
    if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
        # Use root credentials - user needs database creation
        DB_ADMIN_USER="root"
        DB_ADMIN_PASSWORD="$MYSQL_ROOT_PASSWORD"
        print_step "Using MySQL root credentials for database setup"
    else
        # Use provided user credentials - user can create databases
        DB_ADMIN_USER="$DB_USER"
        DB_ADMIN_PASSWORD="$DB_PASSWORD"
        print_step "Using provided user credentials for database setup"
    fi
    
    # Test database connection
    print_step "Testing database connection"
    
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASSWORD" -e "SELECT 1;" &> /dev/null
    if [[ $? -ne 0 ]]; then
        print_error "Cannot connect to MySQL server"
        print_error "Please verify that MySQL is running and credentials are correct"
        return 1
    fi
    
    print_success "MySQL connection verified"
    
    # Check if database exists
    print_step "Checking database existence"
    
    DB_EXISTS=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASSWORD" -e "SHOW DATABASES LIKE '$DB_NAME';" | grep -c "$DB_NAME")
    
    if [[ $DB_EXISTS -eq 0 ]]; then
        print_step "Creating database: $DB_NAME"
        
        mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASSWORD" -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        
        if [[ $? -ne 0 ]]; then
            print_error "Failed to create database: $DB_NAME"
            return 1
        fi
        
        print_success "Database created: $DB_NAME"
    else
        print_success "Database already exists: $DB_NAME"
    fi
    
    # Create database user only if using root credentials
    if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
        print_step "Setting up database user"
        
        mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASSWORD" << EOF
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOF

        if [[ $? -ne 0 ]]; then
            print_error "Failed to create database user"
            return 1
        fi
        
        print_success "Database user configured"
    else
        print_step "Database user already has required permissions"
    fi
    
    # Test application database connection
    print_step "Testing application database connection"
    
    cd "$backend_dir"
    
    # Use Symfony console to test database connection
    php bin/console doctrine:query:sql "SELECT 1" --env=prod &> /dev/null
    if [[ $? -ne 0 ]]; then
        print_error "Application cannot connect to database"
        print_error "Please check the database configuration in .env"
        return 1
    fi
    
    print_success "Application database connection verified"
    
    # Run database migrations or create schema
    print_step "Setting up database schema"
    
    # Check if migration files exist
    if [[ -d "migrations" ]] && [[ -n "$(ls -A migrations/ 2>/dev/null | grep -E '\.php$')" ]]; then
        print_step "Found migration files, running migrations"
        
        php bin/console doctrine:migrations:migrate --no-interaction --env=prod 2>&1
        migration_result=$?
        
        if [[ $migration_result -ne 0 ]]; then
            print_warning "Migration failed, attempting to create schema directly"
            
            # Clear any partial schema and recreate
            # Temporarily disable messenger to avoid transport issues
            export MESSENGER_TRANSPORT_DSN=""
            php bin/console doctrine:schema:drop --force --env=prod 2>/dev/null || true
            php bin/console doctrine:schema:create --env=prod 2>&1
            schema_result=$?
            unset MESSENGER_TRANSPORT_DSN
            
            if [[ $schema_result -ne 0 ]]; then
                print_error "Failed to create database schema"
                return 1
            fi
            
            print_success "Database schema created directly"
        else
            print_success "Database migrations completed"
        fi
    else
        print_step "No migration files found, creating schema directly"
        
        # Debug: Check what's in the .env file
        print_step "Checking current .env configuration"
        echo "Current MESSENGER_TRANSPORT_DSN in .env:"
        grep MESSENGER_TRANSPORT_DSN .env || echo "No MESSENGER_TRANSPORT_DSN found in .env"
        echo "Current environment variables:"
        env | grep MESSENGER || echo "No MESSENGER env vars found"
        
        # Create schema using Doctrine entities
        php bin/console doctrine:schema:create --env=prod 2>&1
        schema_result=$?
        
        if [[ $schema_result -ne 0 ]]; then
            print_error "Failed to create database schema"
            return 1
        fi
        
        print_success "Database schema created from entities"
    fi
    
    # Verify database schema
    print_step "Verifying database schema"
    
    # Check if essential tables exist
    TABLES_COUNT=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SHOW TABLES;" | wc -l)
    
    if [[ $TABLES_COUNT -lt 5 ]]; then
        print_error "Database schema verification failed: insufficient tables created"
        return 1
    fi
    
    # Check specific required tables
    REQUIRED_TABLES=("user" "design" "template" "shape" "media")
    
    for table in "${REQUIRED_TABLES[@]}"; do
        TABLE_EXISTS=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SHOW TABLES LIKE '$table';" | grep -c "$table")
        
        if [[ $TABLE_EXISTS -eq 0 ]]; then
            print_warning "Required table not found: $table"
        fi
    done
    
    print_success "Database schema verification completed"
    
    # Load initial data if fixtures exist
    print_step "Loading initial data"
    
    # Check if fixtures command exists and fixtures are available
    if php bin/console list --env=prod | grep -q "doctrine:fixtures:load" 2>/dev/null; then
        print_step "Loading database fixtures"
        php bin/console doctrine:fixtures:load --no-interaction --env=prod 2>&1
        if [[ $? -eq 0 ]]; then
            print_success "Database fixtures loaded"
        else
            print_warning "Failed to load fixtures, continuing with empty database"
        fi
    else
        print_step "No fixtures available, database ready for use"
    fi
    
    # Create database indexes for performance (if not created by migrations)
    print_step "Optimizing database performance"
    
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << 'EOF'
-- Add indexes for common queries (these may already exist)
-- User table
CREATE INDEX IF NOT EXISTS idx_user_email ON user(email);
CREATE INDEX IF NOT EXISTS idx_user_created_at ON user(created_at);

-- Design table  
CREATE INDEX IF NOT EXISTS idx_design_user_id ON design(user_id);
CREATE INDEX IF NOT EXISTS idx_design_created_at ON design(created_at);
CREATE INDEX IF NOT EXISTS idx_design_status ON design(status);

-- Template table
CREATE INDEX IF NOT EXISTS idx_template_category ON template(category);
CREATE INDEX IF NOT EXISTS idx_template_featured ON template(featured);
CREATE INDEX IF NOT EXISTS idx_template_created_at ON template(created_at);

-- Media table
CREATE INDEX IF NOT EXISTS idx_media_user_id ON media(user_id);
CREATE INDEX IF NOT EXISTS idx_media_type ON media(type);
CREATE INDEX IF NOT EXISTS idx_media_created_at ON media(created_at);

-- Shape table
CREATE INDEX IF NOT EXISTS idx_shape_category ON shape(category);
CREATE INDEX IF NOT EXISTS idx_shape_featured ON shape(featured);
EOF

    print_success "Database optimization completed"
    
    # Set up database maintenance
    print_step "Setting up database maintenance"
    
    # Create a simple backup script
    cat > /usr/local/bin/iamgickpro-backup << EOF
#!/bin/bash
# IAMGickPro Database Backup Script
BACKUP_DIR="/var/backups/iamgickpro"
DATE=\$(date +%Y%m%d_%H%M%S)
mkdir -p "\$BACKUP_DIR"

mysqldump -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" \
  --single-transaction --routines --triggers "$DB_NAME" | \
  gzip > "\$BACKUP_DIR/iamgickpro_\$DATE.sql.gz"

# Keep only last 7 days of backups
find "\$BACKUP_DIR" -name "iamgickpro_*.sql.gz" -mtime +7 -delete
EOF

    chmod +x /usr/local/bin/iamgickpro-backup
    
    # Add weekly backup cron job
    (crontab -l 2>/dev/null; echo "0 2 * * 0 /usr/local/bin/iamgickpro-backup") | crontab -
    
    print_success "Database maintenance configured"
    
    print_success "Database setup completed"
}

# Run the setup
setup_database
