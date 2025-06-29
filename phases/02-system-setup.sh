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

# Check if package is available
package_available() {
    local package="$1"
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        # For apt, check if package exists or if it's provided by another package
        apt-cache show "$package" &>/dev/null || apt-cache search "^${package}$" | grep -q "$package"
    elif [[ "$PKG_MANAGER" == "yum" ]]; then
        yum list "$package" &>/dev/null
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        dnf list "$package" &>/dev/null
    else
        return 1
    fi
}

# Install package with error handling
install_package_safe() {
    local package="$1"
    local optional="${2:-false}"
    
    printf "  Checking %s... " "$package"
    
    if package_available "$package"; then
        printf "available, installing... "
        if $PKG_INSTALL "$package" &>/dev/null; then
            printf "${GREEN}✓${NC}\n"
            log "Successfully installed: $package"
            return 0
        else
            if [[ "$optional" == "true" ]]; then
                printf "${YELLOW}failed (optional)${NC}\n"
                print_warning "Failed to install optional package: $package"
                log "Failed to install optional package: $package"
                return 1
            else
                printf "${RED}✗${NC}\n"
                print_error "Failed to install required package: $package"
                log "Failed to install required package: $package"
                exit 1
            fi
        fi
    else
        if [[ "$optional" == "true" ]]; then
            printf "${YELLOW}not available (optional)${NC}\n"
            log "Package not available: $package (optional)"
            return 1
        else
            printf "${RED}not available${NC}\n"
            print_error "Required package not available: $package"
            log "Required package not available: $package"
            exit 1
        fi
    fi
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
    print_step "Installing PHP 8.4 and extensions"
    
    # Core PHP packages that are commonly available
    local core_php_packages=(
        "php8.4-common"
        "php8.4-cli"
        "php8.4-fpm"
        "php8.4-curl"
        "php8.4-gd"
        "php8.4-intl"
        "php8.4-mbstring"
        "php8.4-opcache"
        "php8.4-xml"
        "php8.4-zip"
        "php8.4-bcmath"
    )
    
    # Database extensions (commonly available)
    local db_packages=(
        "php8.4-mysql"
        "php8.4-sqlite3"
    )
    
    # Optional extensions (may not be available in all repositories)
    local optional_packages=(
        "php8.4-pgsql"
        "php8.4-soap"
        "php8.4-readline"
    )
    
    # Extensions that need to be installed via PECL or are rarely available
    local pecl_packages=(
        "php8.4-redis"
        "php8.4-imagick"
        "php8.4-xdebug"
        "php8.4-memcached"
    )
    
    if [[ "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "dnf" ]]; then
        # Adjust package names for RHEL-based systems
        core_php_packages=(
            "php-common"
            "php-cli"
            "php-fpm"
            "php-curl"
            "php-gd"
            "php-intl"
            "php-mbstring"
            "php-opcache"
            "php-xml"
            "php-zip"
            "php-bcmath"
        )
        
        db_packages=(
            "php-mysqlnd"
            "php-sqlite3"
        )
        
        optional_packages=(
            "php-pgsql"
            "php-soap"
        )
        
        pecl_packages=(
            "php-redis"
            "php-pecl-imagick"
        )
    fi
    
    # Install core packages first (these are essential)
    print_step "Installing core PHP packages..."
    for package in "${core_php_packages[@]}"; do
        install_package_safe "$package" false
    done
    
    # Install database packages (MySQL is essential, others optional)
    print_step "Installing PHP database extensions..."
    for package in "${db_packages[@]}"; do
        if [[ "$package" == "php8.4-mysql" || "$package" == "php-mysqlnd" ]]; then
            install_package_safe "$package" false  # MySQL is required
        else
            install_package_safe "$package" true   # Others are optional
        fi
    done
    
    # Install optional packages
    print_step "Installing optional PHP extensions..."
    for package in "${optional_packages[@]}"; do
        install_package_safe "$package" true
    done
    
    # Try to install PECL packages (these often fail, so make them optional)
    print_step "Installing PECL extensions (if available)..."
    for package in "${pecl_packages[@]}"; do
        install_package_safe "$package" true
    done
    
    # Verify PHP installation
    if ! php -v | grep -q "8.4"; then
        print_error "PHP 8.4 installation failed"
        exit 1
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
    
    # Install Node.js using NodeSource repository
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash - &
    spinner
    wait $!
    
    $PKG_INSTALL nodejs &
    spinner
    wait $!
    
    # Verify installation
    if ! command -v node &> /dev/null; then
        print_error "Node.js installation failed"
        exit 1
    fi
    
    # Install global packages
    npm install -g npm@latest &
    spinner
    wait $!
    
    print_success "Node.js $NODE_VERSION installed"
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
        
        # Enable extensions (only if they're available)
        if package_available "php8.4-gd" || php -m | grep -q "gd"; then
            echo "extension=gd" >> "$php_ini"
        fi
        
        if package_available "php8.4-imagick" || php -m | grep -q "imagick"; then
            echo "extension=imagick" >> "$php_ini"
        fi
        
        # These should always be available
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

# Main system setup function
setup_system() {
    detect_package_manager
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
