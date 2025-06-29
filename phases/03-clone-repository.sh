#!/bin/bash

# Phase 3: Repository Cloning
# Clones the main repository and shapes repository

clone_main_repository() {
    print_step "Cloning IAMGickPro repository"
    
    # Remove existing temp directory if it exists
    if [[ -d "$TEMP_DIR/iamgickpro" ]]; then
        rm -rf "$TEMP_DIR/iamgickpro"
    fi
    
    # Clone the repository
    cd "$TEMP_DIR"
    git clone --depth 1 "$REPO_URL" iamgickpro &
    spinner
    wait $!
    
    if [[ ! -d "$TEMP_DIR/iamgickpro" ]]; then
        print_error "Failed to clone repository"
        exit 1
    fi
    
    print_success "Repository cloned successfully"
    log "Repository cloned to $TEMP_DIR/iamgickpro"
}

clone_shapes_repository() {
    print_step "Cloning shapes repository"
    
    # Clone shapes repository to temporary location
    cd "$TEMP_DIR"
    git clone -b output-only --depth 1 "$SHAPES_REPO_URL" shapes &
    spinner
    wait $!
    
    if [[ ! -d "$TEMP_DIR/shapes" ]]; then
        print_warning "Failed to clone shapes repository - shapes import will be skipped"
        log_warning "Shapes repository not available"
        return 0
    fi
    
    print_success "Shapes repository cloned successfully"
    log "Shapes repository cloned to $TEMP_DIR/shapes"
}

verify_repository_structure() {
    print_step "Verifying repository structure"
    
    local required_dirs=(
        "$TEMP_DIR/iamgickpro/backend"
        "$TEMP_DIR/iamgickpro/frontend"
        "$TEMP_DIR/iamgickpro/scripts"
    )
    
    local required_files=(
        "$TEMP_DIR/iamgickpro/backend/composer.json"
        "$TEMP_DIR/iamgickpro/frontend/package.json"
        "$TEMP_DIR/iamgickpro/backend/.env.local.example"
        "$TEMP_DIR/iamgickpro/frontend/.env.example"
    )
    
    # Check required directories
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            print_error "Missing required directory: $dir"
            exit 1
        fi
    done
    
    # Check required files
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            print_error "Missing required file: $file"
            exit 1
        fi
    done
    
    print_success "Repository structure verified"
}

# Main repository cloning function
clone_repositories() {
    clone_main_repository
    clone_shapes_repository
    verify_repository_structure
    
    print_success "Repository cloning completed"
}

# Execute repository cloning
clone_repositories
