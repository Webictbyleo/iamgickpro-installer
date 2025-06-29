#!/bin/bash

# Phase 8: Content Import
# Imports templates and shapes into the database

import_content() {
    print_step "Importing application content"
    
    local backend_dir="$INSTALL_DIR/backend"
    local shapes_dir="$TEMP_DIR/shapes"
    local scripts_dir="$TEMP_DIR/iamgickpro/scripts"
    
    cd "$backend_dir"
    
    # Import shapes using Symfony command
    print_step "Importing vector shapes"
    
    if [[ ! -d "$shapes_dir" ]]; then
        print_error "Shapes directory not found: $shapes_dir"
        return 1
    fi
    
    # Copy shapes to backend storage directory (required by import service)
    print_step "Copying shapes to backend storage"
    
    mkdir -p storage/shapes
    
    # Remove existing shapes if any
    if [[ -d "storage/shapes" ]]; then
        rm -rf storage/shapes/*
    fi
    
    # Copy all content from temp shapes directory
    cp -r "$shapes_dir"/* storage/shapes/ 2>/dev/null || {
        print_error "Failed to copy shapes to storage directory"
        return 1
    }
    
    print_success "Shapes copied to backend storage"
    
    # Run the shape import command
    php bin/console app:shapes:import --force --env=prod &
    spinner
    wait $!
    
    if [[ $? -ne 0 ]]; then
        print_error "Shape import failed"
        return 1
    fi
    
    print_success "Vector shapes imported"
    
    # Verify shape import
    print_step "Verifying shape import"
    
    SHAPE_COUNT=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -se "SELECT COUNT(*) FROM shapes;")
    
    if [[ $SHAPE_COUNT -eq 0 ]]; then
        print_warning "No shapes were imported"
    else
        print_success "$SHAPE_COUNT shapes imported successfully"
    fi
    
    # Import templates using Node.js script
    print_step "Importing design templates"
    
    # Verify Node.js is available
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed or not in PATH"
        print_error "Please install Node.js and try again"
        return 1
    fi
    
    if [[ ! -f "$scripts_dir/advanced-template-importer.js" ]]; then
        print_error "Template importer script not found: $scripts_dir/advanced-template-importer.js"
        return 1
    fi
    
    # Navigate to scripts directory
    cd "$scripts_dir"
    
    # Install Node.js dependencies for the importer
    if [[ -f "package.json" ]]; then
        print_step "Installing template importer dependencies"
        
        # Check Node.js version
        CURRENT_NODE_VERSION=$(node --version 2>/dev/null || echo "not found")
        CURRENT_NODE_MAJOR=$(echo "$CURRENT_NODE_VERSION" | sed 's/v//' | cut -d. -f1)
        print_step "Node.js version: $CURRENT_NODE_VERSION"
        
        # Warn if using a different Node.js version than expected
        if [[ "$CURRENT_NODE_MAJOR" != "$NODE_VERSION" ]]; then
            print_warning "Expected Node.js $NODE_VERSION but found $CURRENT_NODE_VERSION"
            print_warning "This may cause compatibility issues with canvas package"
            
            # Check if the correct Node.js version is available
            if command -v "node$NODE_VERSION" &> /dev/null; then
                print_step "Using node$NODE_VERSION instead"
                alias node="node$NODE_VERSION"
                alias npm="npm$NODE_VERSION"
            elif [[ -f "/usr/bin/node$NODE_VERSION" ]]; then
                print_step "Using /usr/bin/node$NODE_VERSION instead"
                export PATH="/usr/bin:$PATH"
                alias node="node$NODE_VERSION"
                alias npm="npm$NODE_VERSION"
            fi
        fi
        
        
        
        # Check if node_modules already exists
        if [[ -d "node_modules" ]]; then
            print_step "Dependencies already installed, skipping npm install"
        else
            # Run npm install with timeout and error handling
            print_step "Installing Node.js dependencies (this may take a few minutes)"
            print_step "Working directory: $(pwd)"
            print_step "Running: npm install"
            
            # Clear npm cache first to avoid issues
            npm cache clean --force 2>/dev/null || true
            
            # Run npm install without output redirection to see real-time output
            timeout 600 npm install --verbose
            npm_exit_code=$?
            
            if [[ $npm_exit_code -eq 124 ]]; then
                print_warning "npm install timed out after 10 minutes"
                print_step "Attempting to continue with existing dependencies"
            elif [[ $npm_exit_code -ne 0 ]]; then
                print_warning "npm install failed (exit code: $npm_exit_code)"
                print_step "Attempting to continue anyway - some features may not work"
            else
                print_success "Template importer dependencies installed"
            fi
        fi
    else
        print_warning "No package.json found in scripts directory"
    fi
    
    # Set environment variable for database connection
    export DATABASE_URL="mysql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME"
    
    # Set backend directory for the importer script
    export BACKEND_DIR="$backend_dir"
    
    # Run template import with production settings
    print_step "Running template import"
    
    # Check if the importer script exists and is readable
    if [[ ! -r "advanced-template-importer.js" ]]; then
        print_error "Template importer script is not readable"
        return 1
    fi
    
    # Run the template import with timeout and better error handling
    print_step "Starting template import (this may take several minutes)"
    print_step "Database URL: mysql://$DB_USER:***@$DB_HOST:$DB_PORT/$DB_NAME"
    print_step "Backend directory: $backend_dir"
    timeout 600 node advanced-template-importer.js --limit 50 --force --backend-dir="$backend_dir"
    import_exit_code=$?
    
    if [[ $import_exit_code -eq 124 ]]; then
        print_warning "Template import timed out after 10 minutes, but may have partially completed"
    elif [[ $import_exit_code -ne 0 ]]; then
        print_warning "Template import completed with exit code $import_exit_code (this may be normal for production)"
    else
        print_success "Templates imported successfully"
    fi
    
    # Verify template import
    print_step "Verifying template import"
    
    cd "$backend_dir"
    
    TEMPLATE_COUNT=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -se "SELECT COUNT(*) FROM templates;")
    
    if [[ $TEMPLATE_COUNT -eq 0 ]]; then
        print_warning "No templates were imported"
    else
        print_success "$TEMPLATE_COUNT templates imported successfully"
    fi
    
    # Set up content directories and permissions
    print_step "Setting up content directories"
    
    mkdir -p public/uploads/templates/thumbnails
    mkdir -p public/uploads/templates/previews
    mkdir -p public/uploads/shapes
    mkdir -p public/uploads/media
    
    chown -R www-data:www-data public/uploads/
    chmod -R 775 public/uploads/
    
    print_success "Content directories configured"
    
    # Create content management commands
    print_step "Setting up content management"
    
    # Create a simple content update script
    cat > /usr/local/bin/iamgickpro-update-content << EOF
#!/bin/bash
# IAMGickPro Content Update Script

cd "$backend_dir"

echo "Updating shapes..."
php bin/console app:shapes:import --force --env=prod

echo "Updating templates..."
cd "$scripts_dir"
export DATABASE_URL="mysql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME"
export BACKEND_DIR="$backend_dir"
node advanced-template-importer.js --clear-existing --limit 100 --backend-dir="$backend_dir"

echo "Content update completed"
EOF

    chmod +x /usr/local/bin/iamgickpro-update-content
    
    print_success "Content management tools installed"
    
    # Optimize content for production
    print_step "Optimizing content for production"
    
    # Generate additional image sizes if needed
    php bin/console app:media:optimize --env=prod &> /dev/null || true
    
    # Clear and warm cache to include new content
    php bin/console cache:clear --env=prod
    php bin/console cache:warmup --env=prod
    
    print_success "Content optimization completed"
    
    # Generate content statistics
    print_step "Generating content statistics"
    
    echo "Content Import Summary:" > /tmp/content-summary.txt
    echo "======================" >> /tmp/content-summary.txt
    echo "Shapes imported: $SHAPE_COUNT" >> /tmp/content-summary.txt
    echo "Templates imported: $TEMPLATE_COUNT" >> /tmp/content-summary.txt
    echo "Import completed at: $(date)" >> /tmp/content-summary.txt
    
    cat /tmp/content-summary.txt
    
    print_success "Content import completed"
}

# Run the import
import_content
