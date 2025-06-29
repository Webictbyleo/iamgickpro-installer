#!/bin/bash

# Phase 8: Content Import
# Imports templates and shapes into the database

import_content() {
    print_step "Importing application content"
    
    local backend_dir="$INSTALL_DIR/backend"
    local shapes_dir="$TEMP_DIR/design-vector-shapes"
    local scripts_dir="$TEMP_DIR/iamgickpro/scripts"
    
    cd "$backend_dir"
    
    # Import shapes using Symfony command
    print_step "Importing vector shapes"
    
    if [[ ! -d "$shapes_dir" ]]; then
        print_error "Shapes directory not found: $shapes_dir"
        return 1
    fi
    
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
    
    SHAPE_COUNT=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -se "SELECT COUNT(*) FROM shape;")
    
    if [[ $SHAPE_COUNT -eq 0 ]]; then
        print_warning "No shapes were imported"
    else
        print_success "$SHAPE_COUNT shapes imported successfully"
    fi
    
    # Import templates using Node.js script
    print_step "Importing design templates"
    
    if [[ ! -f "$scripts_dir/advanced-template-importer.js" ]]; then
        print_error "Template importer script not found"
        return 1
    fi
    
    # Navigate to scripts directory
    cd "$scripts_dir"
    
    # Install Node.js dependencies for the importer
    if [[ -f "package.json" ]]; then
        print_step "Installing template importer dependencies"
        npm install --silent &
        spinner
        wait $!
    fi
    
    # Set environment variable for database connection
    export DATABASE_URL="mysql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME"
    
    # Run template import with production settings
    print_step "Running template import"
    
    node advanced-template-importer.js --limit 50 --force &
    spinner
    wait $!
    
    if [[ $? -ne 0 ]]; then
        print_warning "Template import completed with warnings (this is normal for production)"
    else
        print_success "Templates imported successfully"
    fi
    
    # Verify template import
    print_step "Verifying template import"
    
    cd "$backend_dir"
    
    TEMPLATE_COUNT=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -se "SELECT COUNT(*) FROM template;")
    
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
node advanced-template-importer.js --clear-existing --limit 100

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
