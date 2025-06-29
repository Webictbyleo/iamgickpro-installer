#!/bin/bash

# Phase 1: User Input Collection
# Collects all necessary configuration from the user

collect_user_input() {
    print_step "Collecting configuration information"
    echo
    echo -e "${WHITE}Please provide the following information:${NC}"
    echo
    
    # Domain name
    while [[ -z "$DOMAIN_NAME" ]]; do
        read -p "Domain name (e.g., mydesignstudio.com): " DOMAIN_NAME
        if [[ -z "$DOMAIN_NAME" ]]; then
            print_warning "Domain name is required"
        fi
    done
    FRONTEND_URL="https://$DOMAIN_NAME"
    
    # Database configuration
    echo
    echo -e "${CYAN}Database Configuration:${NC}"
    
    while [[ -z "$DB_NAME" ]]; do
        read -p "Database name [iamgickpro]: " DB_NAME
        DB_NAME=${DB_NAME:-iamgickpro}
    done
    
    while [[ -z "$DB_USER" ]]; do
        read -p "Database username [iamgickpro]: " DB_USER
        DB_USER=${DB_USER:-iamgickpro}
    done
    
    while [[ -z "$DB_PASSWORD" ]]; do
        read -s -p "Database password: " DB_PASSWORD
        echo
        if [[ -z "$DB_PASSWORD" ]]; then
            print_warning "Database password is required"
        fi
    done
    
    # MySQL root password (for database creation)
    while [[ -z "$MYSQL_ROOT_PASSWORD" ]]; do
        read -s -p "MySQL root password: " MYSQL_ROOT_PASSWORD
        echo
        if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
            print_warning "MySQL root password is required for database creation"
        fi
    done
    
    # Advanced database settings
    read -p "Database host [$DB_HOST]: " input
    DB_HOST=${input:-$DB_HOST}
    
    read -p "Database port [$DB_PORT]: " input
    DB_PORT=${input:-$DB_PORT}
    
    # Admin account
    echo
    echo -e "${CYAN}Admin Account:${NC}"
    
    while [[ -z "$ADMIN_EMAIL" ]]; do
        read -p "Admin email: " ADMIN_EMAIL
        if [[ ! "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_warning "Please enter a valid email address"
            ADMIN_EMAIL=""
        fi
    done
    
    while [[ -z "$ADMIN_PASSWORD" ]]; do
        read -s -p "Admin password (min 8 characters): " ADMIN_PASSWORD
        echo
        if [[ ${#ADMIN_PASSWORD} -lt 8 ]]; then
            print_warning "Password must be at least 8 characters long"
            ADMIN_PASSWORD=""
        fi
    done
    
    # Application settings
    echo
    echo -e "${CYAN}Application Settings:${NC}"
    
    read -p "Application name [$APP_NAME]: " input
    APP_NAME=${input:-$APP_NAME}
    
    read -p "Mail from address [$ADMIN_EMAIL]: " MAIL_FROM_ADDRESS
    MAIL_FROM_ADDRESS=${MAIL_FROM_ADDRESS:-$ADMIN_EMAIL}
    
    # External API keys (optional)
    echo
    echo -e "${CYAN}External Services (Optional):${NC}"
    
    read -p "Unsplash API key (for stock photos): " UNSPLASH_API_KEY
    read -p "Pexels API key (for stock photos): " PEXELS_API_KEY
    
    # Installation options
    echo
    echo -e "${CYAN}Installation Options:${NC}"
    
    read -p "Install ImageMagick from source? (Y/n): " -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        INSTALL_IMAGEMAGICK=false
    fi
    
    read -p "Install FFmpeg from source? (Y/n): " -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        INSTALL_FFMPEG=false
    fi
    
    read -p "Node.js version [$NODE_VERSION]: " input
    NODE_VERSION=${input:-$NODE_VERSION}
    
    # Confirmation
    echo
    echo -e "${WHITE}Configuration Summary:${NC}"
    echo -e "${CYAN}Domain:${NC} $DOMAIN_NAME"
    echo -e "${CYAN}Database:${NC} $DB_NAME @ $DB_HOST:$DB_PORT"
    echo -e "${CYAN}Database User:${NC} $DB_USER"
    echo -e "${CYAN}Admin Email:${NC} $ADMIN_EMAIL"
    echo -e "${CYAN}App Name:${NC} $APP_NAME"
    echo -e "${CYAN}ImageMagick:${NC} $INSTALL_IMAGEMAGICK"
    echo -e "${CYAN}FFmpeg:${NC} $INSTALL_FFMPEG"
    echo -e "${CYAN}Node.js:${NC} $NODE_VERSION"
    echo
    
    while true; do
        read -p "Is this configuration correct? (Y/n): " -r
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
    
    # Save configuration for recovery
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
    
    # Test MySQL root connection
    if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" &>/dev/null; then
        print_error "Cannot connect to MySQL with root credentials"
        print_error "Please check your MySQL root password and ensure MySQL is running"
        exit 1
    fi
    
    print_success "Database connection validated"
}

# Execute user input collection
collect_user_input
validate_database_connection
