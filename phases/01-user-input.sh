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
    
    # MySQL root password (for database creation)
    while [[ -z "$MYSQL_ROOT_PASSWORD" ]]; do
        printf "MySQL root password: "
        read -sr MYSQL_ROOT_PASSWORD </dev/tty
        echo
        if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
            print_warning "MySQL root password is required for database creation"
        fi
    done
    
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
    
    # Installation options
    echo
    echo -e "${CYAN}Installation Options:${NC}"
    
    printf "Install ImageMagick from source? (Y/n): "
    read -r REPLY </dev/tty
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        INSTALL_IMAGEMAGICK=false
    fi
    
    printf "Install FFmpeg from source? (Y/n): "
    read -r REPLY </dev/tty
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        INSTALL_FFMPEG=false
    fi
    
    printf "Node.js version [$NODE_VERSION]: "
    read -r input </dev/tty
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
