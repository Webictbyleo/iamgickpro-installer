#!/bin/bash

# Phase 1: User Input Collection
# Collects all necessary configuration from the user

# Check for cached configuration
check_cached_config() {
    local cached_config="$CONFIG_CACHE/config.env"
    
    if [[ -f "$cached_config" ]]; then
        print_step "Found cached configuration from previous installation"
        
        # Load cached configuration
        source "$cached_config"
        
        echo
        echo -e "${CYAN}Cached Configuration Found:${NC}"
        echo -e "${CYAN}Domain:${NC} ${DOMAIN_NAME:-'(not set)'}"
        echo -e "${CYAN}Database:${NC} ${DB_NAME:-'(not set)'} @ ${DB_HOST:-'localhost'}:${DB_PORT:-'3306'}"
        echo -e "${CYAN}Database User:${NC} ${DB_USER:-'(not set)'}"
        echo -e "${CYAN}Admin Email:${NC} ${ADMIN_EMAIL:-'(not set)'}"
        echo -e "${CYAN}Admin Name:${NC} ${ADMIN_FIRST_NAME:-'(not set)'} ${ADMIN_LAST_NAME:-'(not set)'}"
        echo -e "${CYAN}App Name:${NC} ${APP_NAME:-'IAMGickPro'}"
        echo -e "${CYAN}Node.js:${NC} ${NODE_VERSION:-'21'}"
        echo -e "${CYAN}Last Updated:${NC} $(date -r "$cached_config" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'unknown')"
        echo
        
        while true; do
            printf "Use this cached configuration? (Y/n): "
            read -r REPLY </dev/tty
            echo
            case $REPLY in
                [Yy]*|"") 
                    print_success "Using cached configuration"
                    log "Using cached configuration from $cached_config"
                    return 0
                    ;;
                [Nn]*) 
                    print_step "Starting fresh configuration"
                    log "User chose to reconfigure instead of using cache"
                    return 1
                    ;;
                *) 
                    echo "Please answer yes (y) or no (n)." 
                    ;;
            esac
        done
    else
        log "No cached configuration found, starting fresh"
        return 1
    fi
}

# Save configuration to cache
save_config_cache() {
    local cached_config="$CONFIG_CACHE/config.env"
    
    print_step "Saving configuration for future use"
    
    cat > "$cached_config" << EOF
# IAMGickPro Installation Configuration
# Generated: $(date)
# This file is automatically created and can be safely deleted to force reconfiguration

DOMAIN_NAME="$DOMAIN_NAME"
DB_HOST="$DB_HOST"
DB_PORT="$DB_PORT"
DB_NAME="$DB_NAME"
DB_USER="$DB_USER"
DB_PASSWORD="$DB_PASSWORD"
MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
ADMIN_EMAIL="$ADMIN_EMAIL"
ADMIN_PASSWORD="$ADMIN_PASSWORD"
ADMIN_FIRST_NAME="$ADMIN_FIRST_NAME"
ADMIN_LAST_NAME="$ADMIN_LAST_NAME"
APP_NAME="$APP_NAME"
MAIL_FROM_ADDRESS="$MAIL_FROM_ADDRESS"
FRONTEND_URL="$FRONTEND_URL"
UNSPLASH_API_KEY="$UNSPLASH_API_KEY"
PEXELS_API_KEY="$PEXELS_API_KEY"
INSTALL_IMAGEMAGICK="$INSTALL_IMAGEMAGICK"
INSTALL_FFMPEG="$INSTALL_FFMPEG"
NODE_VERSION="$NODE_VERSION"
EOF
    
    chmod 600 "$cached_config"  # Secure the config file
    print_success "Configuration cached at $cached_config"
    log "Configuration saved to cache: $cached_config"
}

# Collect user input
collect_user_input() {
    print_step "Collecting configuration information"
    echo
    echo -e "${WHITE}Please provide the following information:${NC}"
    echo
    
    # Domain name
    while [[ -z "$DOMAIN_NAME" ]]; do
        printf "Domain name (e.g., mydesignstudio.com): "
        read -r DOMAIN_NAME </dev/tty
        if [[ -z "$DOMAIN_NAME" ]]; then
            print_warning "Domain name is required"
        fi
    done
    FRONTEND_URL="https://$DOMAIN_NAME"
    
    # Database configuration
    echo
    echo -e "${CYAN}Database Configuration:${NC}"
    
    while [[ -z "$DB_NAME" ]]; do
        printf "Database name [iamgickpro]: "
        read -r DB_NAME </dev/tty
        DB_NAME=${DB_NAME:-iamgickpro}
    done
    
    while [[ -z "$DB_USER" ]]; do
        printf "Database username [iamgickpro]: "
        read -r DB_USER </dev/tty
        DB_USER=${DB_USER:-iamgickpro}
    done
    
    while [[ -z "$DB_PASSWORD" ]]; do
        printf "Database password: "
        read -sr DB_PASSWORD </dev/tty
        echo
        if [[ -z "$DB_PASSWORD" ]]; then
            print_warning "Database password is required"
        fi
    done
    
    # Test if the database user can create databases
    print_step "Testing database permissions"
    
    # First, check if we can connect with the provided credentials
    if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "SELECT 1;" &>/dev/null 2>&1; then
        print_success "Database user can connect"
        
        # Test if user can create databases
        if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS test_db_permission_check; DROP DATABASE IF EXISTS test_db_permission_check;" &>/dev/null 2>&1; then
            print_success "Database user has sufficient privileges to create databases"
            MYSQL_ROOT_PASSWORD=""  # We don't need root password
        else
            print_warning "Database user cannot create databases, will need MySQL root access"
            # Ask for MySQL root password
            while [[ -z "$MYSQL_ROOT_PASSWORD" ]]; do
                printf "MySQL root password (needed to create database and user): "
                read -sr MYSQL_ROOT_PASSWORD </dev/tty
                echo
                if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
                    print_warning "MySQL root password is required for database creation"
                fi
            done
        fi
    else
        print_warning "Cannot connect with provided database credentials"
        print_step "Will create database user during installation"
        # Ask for MySQL root password
        while [[ -z "$MYSQL_ROOT_PASSWORD" ]]; do
            printf "MySQL root password (needed to create database and user): "
            read -sr MYSQL_ROOT_PASSWORD </dev/tty
            echo
            if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
                print_warning "MySQL root password is required for database and user creation"
            fi
        done
    fi
    
    # Advanced database settings
    printf "Database host [$DB_HOST]: "
    read -r input </dev/tty
    DB_HOST=${input:-$DB_HOST}
    
    printf "Database port [$DB_PORT]: "
    read -r input </dev/tty
    DB_PORT=${input:-$DB_PORT}
    
    # Admin account
    echo
    echo -e "${CYAN}Admin Account:${NC}"
    
    while [[ -z "$ADMIN_EMAIL" ]]; do
        printf "Admin email: "
        read -r ADMIN_EMAIL </dev/tty
        if [[ ! "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_warning "Please enter a valid email address"
            ADMIN_EMAIL=""
        fi
    done
    
    while [[ -z "$ADMIN_PASSWORD" ]]; do
        printf "Admin password (min 8 characters): "
        read -sr ADMIN_PASSWORD </dev/tty
        echo
        if [[ ${#ADMIN_PASSWORD} -lt 8 ]]; then
            print_warning "Password must be at least 8 characters long"
            ADMIN_PASSWORD=""
        fi
    done
    
    while [[ -z "$ADMIN_FIRST_NAME" ]]; do
        printf "Admin first name: "
        read -r ADMIN_FIRST_NAME </dev/tty
        if [[ -z "$ADMIN_FIRST_NAME" ]]; then
            print_warning "First name cannot be empty"
        fi
    done
    
    while [[ -z "$ADMIN_LAST_NAME" ]]; do
        printf "Admin last name: "
        read -r ADMIN_LAST_NAME </dev/tty
        if [[ -z "$ADMIN_LAST_NAME" ]]; then
            print_warning "Last name cannot be empty"
        fi
    done
    
    # Application settings
    echo
    echo -e "${CYAN}Application Settings:${NC}"
    
    printf "Application name [$APP_NAME]: "
    read -r input </dev/tty
    APP_NAME=${input:-$APP_NAME}
    
    printf "Mail from address [$ADMIN_EMAIL]: "
    read -r MAIL_FROM_ADDRESS </dev/tty
    MAIL_FROM_ADDRESS=${MAIL_FROM_ADDRESS:-$ADMIN_EMAIL}
    
    # External API keys (optional)
    echo
    echo -e "${CYAN}External Services (Optional):${NC}"
    
    printf "Unsplash API key (for stock photos): "
    read -r UNSPLASH_API_KEY </dev/tty
    printf "Pexels API key (for stock photos): "
    read -r PEXELS_API_KEY </dev/tty
    
    # Set required installation options (no user input needed)
    echo
    echo -e "${CYAN}Installation Configuration:${NC}"
    echo -e "${CYAN}• Node.js version: ${WHITE}21${NC} (LTS)"
    echo -e "${CYAN}• ImageMagick: ${WHITE}Will be compiled from source${NC} (required for image processing)"
    echo -e "${CYAN}• FFmpeg: ${WHITE}Will be compiled from source${NC} (required for video processing)"
    echo
    
    # Set the required values
    NODE_VERSION="21"
    INSTALL_IMAGEMAGICK=true
    INSTALL_FFMPEG=true
    
    # Confirmation
    echo
    echo -e "${WHITE}Configuration Summary:${NC}"
    echo -e "${CYAN}Domain:${NC} $DOMAIN_NAME"
    echo -e "${CYAN}Database:${NC} $DB_NAME @ $DB_HOST:$DB_PORT"
    echo -e "${CYAN}Database User:${NC} $DB_USER"
    echo -e "${CYAN}Admin Email:${NC} $ADMIN_EMAIL"
    echo -e "${CYAN}Admin Name:${NC} $ADMIN_FIRST_NAME $ADMIN_LAST_NAME"
    echo -e "${CYAN}App Name:${NC} $APP_NAME"
    echo -e "${CYAN}Node.js:${NC} $NODE_VERSION"
    echo -e "${CYAN}ImageMagick:${NC} Compiled from source"
    echo -e "${CYAN}FFmpeg:${NC} Compiled from source"
    if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
        echo -e "${CYAN}MySQL Root:${NC} Will be used for database setup"
    else
        echo -e "${CYAN}Database Setup:${NC} Using provided user credentials"
    fi
    echo
    
    while true; do
        printf "Is this configuration correct? (Y/n): "
        read -r REPLY </dev/tty
        case $REPLY in
            [Yy]*|"") break ;;
            [Nn]*) 
                echo "Please restart the installer to reconfigure."
                exit 0
                ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
    
    print_success "Configuration collected and confirmed"
    
    # Save configuration for recovery and future use
    save_config_cache
    
    # Also save to temp directory for current installation
    cat > "$TEMP_DIR/config.env" << EOF
DOMAIN_NAME="$DOMAIN_NAME"
DB_HOST="$DB_HOST"
DB_PORT="$DB_PORT"
DB_NAME="$DB_NAME"
DB_USER="$DB_USER"
DB_PASSWORD="$DB_PASSWORD"
MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
ADMIN_EMAIL="$ADMIN_EMAIL"
ADMIN_PASSWORD="$ADMIN_PASSWORD"
APP_NAME="$APP_NAME"
MAIL_FROM_ADDRESS="$MAIL_FROM_ADDRESS"
FRONTEND_URL="$FRONTEND_URL"
UNSPLASH_API_KEY="$UNSPLASH_API_KEY"
PEXELS_API_KEY="$PEXELS_API_KEY"
INSTALL_IMAGEMAGICK="$INSTALL_IMAGEMAGICK"
INSTALL_FFMPEG="$INSTALL_FFMPEG"
NODE_VERSION="$NODE_VERSION"
EOF
    
    log "Configuration saved to $TEMP_DIR/config.env"
}

# Validate database connection
validate_database_connection() {
    print_step "Validating database connection"
    
    if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
        # Test MySQL root connection
        if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" &>/dev/null; then
            print_error "Cannot connect to MySQL with root credentials"
            print_error "Please check your MySQL root password and ensure MySQL is running"
            exit 1
        fi
        print_success "MySQL root connection validated"
    else
        # Validate the database user connection again
        if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "SELECT 1;" &>/dev/null; then
            print_error "Cannot connect to MySQL with provided user credentials"
            print_error "Please check your database credentials and ensure MySQL is running"
            exit 1
        fi
        print_success "Database user connection validated"
    fi
}

# Execute user input collection
check_cached_config || collect_user_input
validate_database_connection
