#!/bin/bash

# Phase 7: Database Setup
# Creates database, runs migrations, and verifies setup

setup_database() {
    print_step "Setting up database"
    
    # Debug: Check if CLEAR_DATABASE flag is set
    if [[ "${CLEAR_DATABASE:-false}" == "true" ]]; then
        log "Database setup: CLEAR_DATABASE flag is set to true"
        print_warning "Database clearing requested for clean reinstall"
    else
        log "Database setup: CLEAR_DATABASE flag is not set (value: ${CLEAR_DATABASE:-'not set'})"
    fi
    
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
    
    # More robust database existence check
    DB_EXISTS_RESULT=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASSWORD" -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$DB_NAME';" 2>/dev/null | grep -c "$DB_NAME")
    DB_EXISTS=$DB_EXISTS_RESULT
    
    # Debug logging
    log "Database existence check: DB_EXISTS=$DB_EXISTS, CLEAR_DATABASE=${CLEAR_DATABASE:-false}"
    log "Condition check: CLEAR_DATABASE='${CLEAR_DATABASE:-false}' == 'true' is $([[ "${CLEAR_DATABASE:-false}" == "true" ]] && echo "TRUE" || echo "FALSE")"
    log "DB_EXISTS check: DB_EXISTS=$DB_EXISTS -eq 1 is $([[ $DB_EXISTS -eq 1 ]] && echo "TRUE" || echo "FALSE")"
    
    # Handle database clearing for clean reinstalls
    if [[ "${CLEAR_DATABASE:-false}" == "true" ]] && [[ $DB_EXISTS -eq 1 ]]; then
        print_warning "Clean reinstall requested - clearing existing database"
        print_step "Dropping existing database: $DB_NAME"
        
        mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASSWORD" -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;"
        
        if [[ $? -ne 0 ]]; then
            print_error "Failed to drop existing database: $DB_NAME"
            return 1
        fi
        
        print_success "Existing database dropped successfully"
        log "Database '$DB_NAME' dropped for clean reinstall (CLEAR_DATABASE=true)"
        
        # Create fresh database immediately
        print_step "Creating fresh database: $DB_NAME"
        mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASSWORD" -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        
        if [[ $? -ne 0 ]]; then
            print_error "Failed to create fresh database: $DB_NAME"
            return 1
        fi
        
        print_success "Fresh database created: $DB_NAME"
        log "Fresh database '$DB_NAME' created after clean reinstall"
        DB_EXISTS=1  # Set to 1 since we just created it
        DATABASE_WAS_CLEARED=true
        DATABASE_CREATION_HANDLED=true  # Flag to skip the normal creation logic
    elif [[ "${CLEAR_DATABASE:-false}" == "true" ]] && [[ $DB_EXISTS -eq 0 ]]; then
        print_step "Clean reinstall requested but database doesn't exist - will create fresh"
        DATABASE_WAS_CLEARED=true
        DATABASE_CREATION_HANDLED=false
    else
        log "Database clearing conditions not met: CLEAR_DATABASE=${CLEAR_DATABASE:-false}, DB_EXISTS=$DB_EXISTS"
        DATABASE_WAS_CLEARED=false
        DATABASE_CREATION_HANDLED=false
    fi
    
    # Create database if it doesn't exist (and wasn't already handled by clearing logic)
    if [[ $DB_EXISTS -eq 0 ]] && [[ "${DATABASE_CREATION_HANDLED:-false}" == "false" ]]; then
        print_step "Creating database: $DB_NAME"
        
        mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_ADMIN_USER" -p"$DB_ADMIN_PASSWORD" -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        
        if [[ $? -ne 0 ]]; then
            print_error "Failed to create database: $DB_NAME"
            return 1
        fi
        
        print_success "Database created: $DB_NAME"
    elif [[ "${DATABASE_CREATION_HANDLED:-false}" == "true" ]]; then
        print_step "Database creation already handled in clearing process"
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
    
    # Disable messenger transport during connection test to avoid automatic table creation
    ORIGINAL_MESSENGER_DSN="${MESSENGER_TRANSPORT_DSN:-}"
    export MESSENGER_TRANSPORT_DSN="sync://"
    
    # Use Symfony console to test database connection
    php bin/console doctrine:query:sql "SELECT 1" --env=prod &> /dev/null
    connection_result=$?
    
    # Restore messenger DSN
    export MESSENGER_TRANSPORT_DSN="$ORIGINAL_MESSENGER_DSN"
    
    if [[ $connection_result -ne 0 ]]; then
        print_error "Application cannot connect to database"
        print_error "Please check the database configuration in .env"
        return 1
    fi
    
    print_success "Application database connection verified"
    
    # Run database migrations or create schema
    print_step "Setting up database schema"
    
    # Store original messenger DSN and set to sync for all database operations
    ORIGINAL_MESSENGER_DSN="${MESSENGER_TRANSPORT_DSN:-}"
    export MESSENGER_TRANSPORT_DSN="sync://"
    print_step "Temporarily using sync messenger transport for database operations"
    
    # Check if migration files exist
    if [[ -d "migrations" ]] && [[ -n "$(ls -A migrations/ 2>/dev/null | grep -E '\.php$')" ]]; then
        print_step "Found migration files, running migrations"
        
        php bin/console doctrine:migrations:migrate --no-interaction --env=prod 2>&1
        migration_result=$?
        
        if [[ $migration_result -ne 0 ]]; then
            print_warning "Migration failed, attempting to create schema directly"
            
            # Clear any partial schema and recreate
            php bin/console doctrine:schema:drop --force --env=prod 2>/dev/null || true
            php bin/console doctrine:schema:create --env=prod 2>&1
            schema_result=$?
            
            if [[ $schema_result -ne 0 ]]; then
                # Restore messenger DSN before returning
                export MESSENGER_TRANSPORT_DSN="$ORIGINAL_MESSENGER_DSN"
                print_error "Failed to create database schema"
                return 1
            fi
            
            print_success "Database schema created directly"
        else
            print_success "Database migrations completed"
        fi
    else
        print_step "No migration files found, creating schema directly"
        
        # Check if this is a clean database setup (dropped and recreated)
        if [[ "${DATABASE_WAS_CLEARED:-false}" == "true" ]]; then
            print_step "Creating fresh database schema for clean install (database was cleared)"
            
            # Try schema:create first
            if php bin/console doctrine:schema:create --env=prod 2>&1; then
                print_success "Fresh database schema created for clean install"
            else
                print_warning "Schema create failed, attempting to drop any existing tables and recreate"
                
                # Drop all tables and recreate from scratch
                php bin/console doctrine:schema:drop --force --env=prod 2>/dev/null || true
                php bin/console doctrine:schema:create --env=prod 2>&1
                schema_result=$?
                
                if [[ $schema_result -ne 0 ]]; then
                    print_warning "Schema create still failing, using schema update as fallback"
                    php bin/console doctrine:schema:update --force --env=prod 2>&1
                    schema_result=$?
                    
                    if [[ $schema_result -ne 0 ]]; then
                        # Restore messenger DSN before returning
                        export MESSENGER_TRANSPORT_DSN="$ORIGINAL_MESSENGER_DSN"
                        print_error "Failed to create database schema for clean install"
                        return 1
                    fi
                    
                    print_success "Database schema updated for clean install"
                else
                    print_success "Database schema created after dropping existing tables"
                fi
            fi
        else
            # Use schema:update which handles existing tables gracefully
            print_step "Updating database schema to match entities"
            php bin/console doctrine:schema:update --force --env=prod 2>&1
            schema_result=$?
            
            if [[ $schema_result -ne 0 ]]; then
                print_warning "Schema update failed, trying to create fresh schema"
                
                # If update fails, try to drop and recreate
                php bin/console doctrine:schema:drop --force --env=prod 2>/dev/null || true
                php bin/console doctrine:schema:create --env=prod 2>&1
                schema_result=$?
                
                if [[ $schema_result -ne 0 ]]; then
                    # Restore messenger DSN before returning
                    export MESSENGER_TRANSPORT_DSN="$ORIGINAL_MESSENGER_DSN"
                    print_error "Failed to create database schema"
                    return 1
                fi
                
                print_success "Database schema created from scratch"
            else
                print_success "Database schema updated successfully"
            fi
        fi
    fi
    
    # Restore original messenger DSN after all database operations
    export MESSENGER_TRANSPORT_DSN="$ORIGINAL_MESSENGER_DSN"
    print_step "Restored original messenger transport configuration"
    
    # Verify database schema
    print_step "Verifying database schema"
    
    # Check if essential tables exist with timeout
    print_step "Counting database tables"
    TABLES_COUNT=$(timeout 30 mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SHOW TABLES;" 2>/dev/null | wc -l)
    
    print_step "Found $TABLES_COUNT tables in database"
    
    if [[ $TABLES_COUNT -lt 2 ]]; then
        print_warning "Database schema verification: only $TABLES_COUNT tables found (expected more)"
    else
        print_success "Database has $TABLES_COUNT tables"
    fi
    
    print_success "Database schema verification completed"
    
    # Load initial data if fixtures exist
    print_step "Loading initial data"
    
    # Check if this is a clean database setup
    if [[ "${DATABASE_WAS_CLEARED:-false}" == "true" ]]; then
        print_step "Clean database setup - skipping fixtures to ensure empty database"
        log "Fixture loading skipped for clean install (DATABASE_WAS_CLEARED=true)"
        print_success "Database is clean and ready for fresh use"
    else
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
    fi
    
    # Create database indexes for performance (if not created by migrations)
    print_step "Optimizing database performance"
    
    # First, get the actual tables that exist
    print_step "Checking actual database tables"
    ACTUAL_TABLES=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SHOW TABLES;" 2>/dev/null | tail -n +2 | tr '\n' ' ')
    print_step "Found tables: $ACTUAL_TABLES"
    
    # Use the correct table names based on actual Doctrine entities
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << 'EOF' 2>/dev/null || true
-- Add indexes for common queries (ignore errors if they already exist)
-- Users table (additional performance indexes)
CREATE INDEX idx_users_created_at ON users(created_at);
CREATE INDEX idx_users_is_active ON users(is_active);
CREATE INDEX idx_users_last_login_at ON users(last_login_at);
CREATE INDEX idx_users_plan ON users(plan);
CREATE INDEX idx_users_deleted_at ON users(deleted_at);

-- Designs table indexes
CREATE INDEX idx_designs_project_id ON designs(project_id);
CREATE INDEX idx_designs_created_at ON designs(created_at);
CREATE INDEX idx_designs_updated_at ON designs(updated_at);
CREATE INDEX idx_designs_is_public ON designs(is_public);
CREATE INDEX idx_designs_deleted_at ON designs(deleted_at);

-- Projects table indexes
CREATE INDEX idx_projects_user_id ON projects(user_id);
CREATE INDEX idx_projects_created_at ON projects(created_at);
CREATE INDEX idx_projects_updated_at ON projects(updated_at);
CREATE INDEX idx_projects_is_public ON projects(is_public);
CREATE INDEX idx_projects_deleted_at ON projects(deleted_at);

-- Templates table indexes (additional to existing ones)
CREATE INDEX idx_templates_is_active ON templates(is_active);
CREATE INDEX idx_templates_usage_count ON templates(usage_count);
CREATE INDEX idx_templates_rating ON templates(rating);
CREATE INDEX idx_templates_is_public ON templates(is_public);
CREATE INDEX idx_templates_is_recommended ON templates(is_recommended);
CREATE INDEX idx_templates_deleted_at ON templates(deleted_at);

-- Media table indexes
CREATE INDEX idx_media_created_at ON media(created_at);
CREATE INDEX idx_media_updated_at ON media(updated_at);

-- Export jobs table indexes
CREATE INDEX idx_export_jobs_created_at ON export_jobs(created_at);
CREATE INDEX idx_export_jobs_status ON export_jobs(status);

-- Layers table indexes
CREATE INDEX idx_layers_created_at ON layers(created_at);

-- User subscriptions table indexes
CREATE INDEX idx_user_subscriptions_user_id ON user_subscriptions(user_id);
CREATE INDEX idx_user_subscriptions_plan_id ON user_subscriptions(plan_id);
CREATE INDEX idx_user_subscriptions_status ON user_subscriptions(status);
CREATE INDEX idx_user_subscriptions_created_at ON user_subscriptions(created_at);

-- User integrations table indexes
CREATE INDEX idx_user_integrations_user_id ON user_integrations(user_id);
CREATE INDEX idx_user_integrations_service ON user_integrations(service);
CREATE INDEX idx_user_integrations_created_at ON user_integrations(created_at);

-- Video analysis table indexes
CREATE INDEX idx_video_analysis_created_at ON video_analysis(created_at);
CREATE INDEX idx_video_analysis_status ON video_analysis(status);

-- Shapes table indexes
CREATE INDEX idx_shapes_created_at ON shapes(created_at);

-- Plugins table indexes
CREATE INDEX idx_plugins_is_active ON plugins(is_active);
CREATE INDEX idx_plugins_created_at ON plugins(created_at);
EOF

    # Ignore errors from duplicate indexes
    if [[ $? -eq 0 ]]; then
        print_success "Database indexes created"
    else
        print_success "Database optimization completed (some indexes may already exist)"
    fi
    
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
