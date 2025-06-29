#!/bin/bash

# Phase 2: System Setup
# Installs and configures system dependencies

# Detect package manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
        PKG_INSTALL="apt-get install -y"
        PKG_UPDATE="apt-get update"
        PKG_UPGRADE="apt-get upgrade -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
        PKG_UPDATE="yum update -y"
        PKG_UPGRADE="yum upgrade -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="dnf install -y"
        PKG_UPDATE="dnf update -y"
        PKG_UPGRADE="dnf upgrade -y"
    else
        print_error "Unsupported package manager"
        exit 1
    fi
    
    log "Detected package manager: $PKG_MANAGER"
}

# Update system packages
update_system() {
    print_step "Updating system packages"
    
    $PKG_UPDATE &
    spinner
    wait $!
    
    print_success "System packages updated"
}

# Install basic dependencies
install_basic_dependencies() {
    print_step "Installing basic dependencies"
    
    local packages=(
        "curl"
        "wget"
        "git"
        "unzip"
        "software-properties-common"
        "apt-transport-https"
        "ca-certificates"
        "gnupg"
        "lsb-release"
        "build-essential"
        "cmake"
        "pkg-config"
        "libtool"
        "autoconf"
        "automake"
        "make"
        "gcc"
        "g++"
    )
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        packages+=("software-properties-common")
    elif [[ "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "dnf" ]]; then
        packages+=("epel-release")
    fi
    
    $PKG_INSTALL "${packages[@]}" &
    spinner
    wait $!
    
    print_success "Basic dependencies installed"
}

# Add PHP 8.4 repository
add_php_repository() {
    print_step "Adding PHP 8.4 repository"
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        # Add Ondrej's PHP repository
        add-apt-repository ppa:ondrej/php -y &
        spinner
        wait $!
        
        $PKG_UPDATE &
        spinner
        wait $!
    elif [[ "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "dnf" ]]; then
        # Add Remi's repository for CentOS/RHEL
        $PKG_INSTALL https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm &
        spinner
        wait $!
        
        $PKG_INSTALL https://rpms.remirepo.net/enterprise/remi-release-8.rpm &
        spinner
        wait $!
        
        if [[ "$PKG_MANAGER" == "dnf" ]]; then
            dnf module reset php -y
            dnf module enable php:remi-8.4 -y
        fi
    fi
    
    print_success "PHP repository added"
}

# Install PHP 8.4 and extensions
install_php() {
    print_step "Installing PHP 8.4 and essential extensions"
    
    # Show information about package selection
    echo -e "${CYAN}ℹ Installing only essential PHP extensions required by IAMGickPro:${NC}"
    echo -e "${CYAN}  • Based on composer.json requirements${NC}"
    echo -e "${CYAN}  • Includes core extensions: common, cli, fpm, dev, mysql, curl, gd, intl, mbstring, opcache, xml, zip, bcmath${NC}"
    echo -e "${CYAN}  • Optional extensions (redis, imagick) will be installed if available${NC}"
    echo
    
    # Core PHP packages required by IAMGickPro (based on composer.json)
    local php_packages=(
        "php8.4-common"
        "php8.4-cli"
        "php8.4-fpm"
        "php8.4-dev"
        "php8.4-mysql"
        "php8.4-curl"
        "php8.4-gd"
        "php8.4-intl"
        "php8.4-mbstring"
        "php8.4-opcache"
        "php8.4-xml"
        "php8.4-zip"
        "php8.4-bcmath"
    )
    
    if [[ "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "dnf" ]]; then
        # Adjust package names for RHEL-based systems
        php_packages=(
            "php"
            "php-common"
            "php-cli"
            "php-fpm"
            "php-devel"
            "php-mysqlnd"
            "php-curl"
            "php-gd"
            "php-intl"
            "php-mbstring"
            "php-opcache"
            "php-xml"
            "php-zip"
            "php-bcmath"
        )
    fi
    
    # Install core PHP packages
    print_step "Installing core PHP packages"
    if ! $PKG_INSTALL "${php_packages[@]}" 2>/dev/null; then
        print_error "Failed to install core PHP packages"
        log_error "Package installation failed: ${php_packages[*]}"
        exit 1
    fi
    
    # Install additional useful extensions (optional)
    local additional_packages=()
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        additional_packages=(
            "php8.4-redis"
            "php8.4-imagick"
        )
    fi
    
    if [[ ${#additional_packages[@]} -gt 0 ]]; then
        print_step "Installing additional PHP extensions"
        for package in "${additional_packages[@]}"; do
            if $PKG_INSTALL "$package" 2>/dev/null; then
                print_success "Installed $package"
                log "Successfully installed optional package: $package"
            else
                print_warning "Optional package $package not available, skipping"
                log_warning "Optional package not available: $package"
            fi
        done
    fi
    
    # Verify PHP installation
    if ! command -v php &> /dev/null; then
        print_error "PHP command not found after installation"
        exit 1
    fi
    
    local php_version
    php_version=$(php -v 2>/dev/null | head -n1 | grep -oP 'PHP \K[0-9]+\.[0-9]+' || echo "unknown")
    
    if [[ "$php_version" != "8.4" ]]; then
        print_warning "PHP version is $php_version, expected 8.4"
        log_warning "PHP version mismatch: expected 8.4, got $php_version"
        
        # Check if PHP 8.4 is available but not default
        if command -v php8.4 &> /dev/null; then
            print_step "Setting PHP 8.4 as default"
            update-alternatives --install /usr/bin/php php /usr/bin/php8.4 84 2>/dev/null || true
            php_version=$(php -v 2>/dev/null | head -n1 | grep -oP 'PHP \K[0-9]+\.[0-9]+' || echo "unknown")
        fi
    fi
    
    print_success "PHP 8.4 and extensions installed"
    log "PHP version: $(php -v | head -n1)"
}

# Install Composer
install_composer() {
    print_step "Installing Composer"
    
    # Download and install Composer
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer &
    spinner
    wait $!
    
    # Verify installation
    if ! command -v composer &> /dev/null; then
        print_error "Composer installation failed"
        exit 1
    fi
    
    print_success "Composer installed"
    log "Composer version: $(composer --version)"
}

# Install Node.js
install_nodejs() {
    print_step "Installing Node.js $NODE_VERSION"
    
    # Check if Node.js is already installed and compatible
    if command -v node &> /dev/null; then
        local current_version
        current_version=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
        
        if [[ "$current_version" == "$NODE_VERSION" ]]; then
            print_success "Node.js $NODE_VERSION is already installed"
            local npm_version
            npm_version=$(npm -v 2>/dev/null || echo "unknown")
            print_success "npm version: $npm_version"
            log "Node.js version: $(node -v)"
            log "npm version: $npm_version"
            return 0
        else
            print_warning "Node.js $current_version found, but need version $NODE_VERSION"
            print_step "Removing existing Node.js installation"
            apt-get remove -y nodejs npm 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
        fi
    fi
    
    # Remove any existing NodeSource repository to avoid conflicts
    print_step "Cleaning up existing Node.js repositories"
    rm -f /etc/apt/sources.list.d/nodesource.list* 2>/dev/null || true
    
    # Install Node.js using NodeSource repository
    print_step "Setting up NodeSource repository for Node.js $NODE_VERSION"
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - 2>/dev/null
    
    print_step "Installing Node.js $NODE_VERSION"
    if ! $PKG_INSTALL nodejs; then
        print_error "Node.js installation failed"
        exit 1
    fi
    
    # Verify installation
    if ! command -v node &> /dev/null; then
        print_error "Node.js command not found after installation"
        exit 1
    fi
    
    # Verify npm is working
    if ! command -v npm &> /dev/null; then
        print_error "npm command not found after installation"
        exit 1
    fi
    
    # Test npm functionality
    print_step "Testing npm functionality"
    if npm --version &>/dev/null; then
        print_success "npm is working correctly"
    else
        print_warning "npm may have compatibility issues, attempting to fix"
        
        # Try to reinstall npm compatible with current Node.js version
        local node_major
        node_major=$(node -v | sed 's/v//' | cut -d. -f1)
        
        if [[ "$node_major" -ge 22 ]]; then
            print_step "Installing latest npm for Node.js $node_major"
            npm install -g npm@latest 2>/dev/null || {
                print_warning "Failed to update npm, using system npm"
            }
        fi
    fi
    
    print_success "Node.js $NODE_VERSION installed successfully"
    log "Node.js version: $(node -v)"
    log "npm version: $(npm -v)"
}

# Install MySQL
install_mysql() {
    print_step "Installing MySQL server"
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        # Set MySQL root password during installation
        echo "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
        echo "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
        
        $PKG_INSTALL mysql-server mysql-client &
        spinner
        wait $!
    else
        $PKG_INSTALL mysql-server mysql &
        spinner
        wait $!
        
        systemctl start mysqld
        systemctl enable mysqld
        
        # Set root password for RHEL-based systems
        mysql_secure_installation <<EOF

y
$MYSQL_ROOT_PASSWORD
$MYSQL_ROOT_PASSWORD
y
y
y
y
EOF
    fi
    
    # Start and enable MySQL
    systemctl start mysql 2>/dev/null || systemctl start mysqld
    systemctl enable mysql 2>/dev/null || systemctl enable mysqld
    
    print_success "MySQL server installed and started"
}

# Install nginx
install_nginx() {
    print_step "Installing nginx"
    
    $PKG_INSTALL nginx &
    spinner
    wait $!
    
    # Start and enable nginx
    systemctl start nginx
    systemctl enable nginx
    
    # Create nginx configuration directory for the app
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    
    print_success "nginx installed and started"
}

# Install Redis (optional but recommended)
install_redis() {
    print_step "Installing Redis"
    
    $PKG_INSTALL redis-server &
    spinner
    wait $!
    
    # Start and enable Redis
    systemctl start redis 2>/dev/null || systemctl start redis-server
    systemctl enable redis 2>/dev/null || systemctl enable redis-server
    
    print_success "Redis installed and started"
}

# Configure PHP
configure_php() {
    print_step "Configuring PHP"
    
    # Find PHP configuration files
    local php_ini="/etc/php/8.4/fpm/php.ini"
    local php_fpm_conf="/etc/php/8.4/fpm/pool.d/www.conf"
    
    if [[ ! -f "$php_ini" ]]; then
        php_ini="/etc/php.ini"
    fi
    
    # Configure PHP settings
    if [[ -f "$php_ini" ]]; then
        # Backup original configuration
        cp "$php_ini" "$php_ini.backup"
        
        # Update PHP settings
        sed -i 's/;max_execution_time = 30/max_execution_time = 300/' "$php_ini"
        sed -i 's/;max_input_time = 60/max_input_time = 300/' "$php_ini"
        sed -i 's/memory_limit = 128M/memory_limit = 512M/' "$php_ini"
        sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 100M/' "$php_ini"
        sed -i 's/post_max_size = 8M/post_max_size = 100M/' "$php_ini"
        sed -i 's/;date.timezone =/date.timezone = UTC/' "$php_ini"
        sed -i 's/;opcache.enable=1/opcache.enable=1/' "$php_ini"
        sed -i 's/;opcache.memory_consumption=128/opcache.memory_consumption=256/' "$php_ini"
        
        # Enable extensions
        echo "extension=gd" >> "$php_ini"
        echo "extension=imagick" >> "$php_ini"
        echo "extension=zip" >> "$php_ini"
        echo "extension=curl" >> "$php_ini"
        echo "extension=mbstring" >> "$php_ini"
        echo "extension=intl" >> "$php_ini"
    fi
    
    # Restart PHP-FPM
    systemctl restart php8.4-fpm 2>/dev/null || systemctl restart php-fpm
    
    print_success "PHP configured"
}

# Configure firewall
configure_firewall() {
    print_step "Configuring firewall"
    
    if command -v ufw &> /dev/null; then
        # Configure UFW
        ufw --force enable
        ufw allow ssh
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 3306/tcp  # MySQL (restrict this in production)
    elif command -v firewall-cmd &> /dev/null; then
        # Configure firewalld
        systemctl start firewalld
        systemctl enable firewalld
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-service=mysql
        firewall-cmd --reload
    fi
    
    print_success "Firewall configured"
}

# Clean up problematic repositories
cleanup_repositories() {
    print_step "Cleaning up problematic repositories"
    
    # Remove webmin repository if it exists and is causing issues
    if [[ -f /etc/apt/sources.list.d/webmin.list ]]; then
        print_step "Removing problematic webmin repository"
        rm -f /etc/apt/sources.list.d/webmin.list
    fi
    
    # Clean up any legacy trusted keys
    if [[ -f /etc/apt/trusted.gpg ]]; then
        print_step "Cleaning up legacy apt keys"
        # Remove the problematic DSA1024 key if it exists
        apt-key del 1719003ACE3E5A41E2DE70DFD97A3AE911F63C51 2>/dev/null || true
    fi
    
    print_success "Repository cleanup completed"
}

# Main system setup function
setup_system() {
    detect_package_manager
    cleanup_repositories
    update_system
    install_basic_dependencies
    add_php_repository
    install_php
    install_composer
    install_nodejs
    install_mysql
    install_nginx
    install_redis
    configure_php
    configure_firewall
    
    print_success "System setup completed"
}

# Execute system setup
setup_system
