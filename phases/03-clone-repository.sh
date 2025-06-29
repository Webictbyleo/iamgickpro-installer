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
    local clone_pid=$!
    spinner
    wait $clone_pid
    local clone_exit_code=$?
    
    if [[ $clone_exit_code -ne 0 ]] || [[ ! -d "$TEMP_DIR/iamgickpro" ]]; then
        print_error "Failed to clone repository (exit code: $clone_exit_code)"
        exit 1
    fi
    
    print_success "Repository cloned successfully"
    log "Repository cloned to $TEMP_DIR/iamgickpro"
}

clone_shapes_repository() {
    print_step "Cloning shapes repository"
    
    # Remove existing shapes directory if it exists
    if [[ -d "$TEMP_DIR/shapes" ]]; then
        rm -rf "$TEMP_DIR/shapes"
    fi
    
    # Clone shapes repository to temporary location
    cd "$TEMP_DIR"
    git clone -b output-only --depth 1 "$SHAPES_REPO_URL" shapes &
    local shapes_clone_pid=$!
    spinner
    wait $shapes_clone_pid
    local shapes_exit_code=$?
    
    if [[ $shapes_exit_code -ne 0 ]] || [[ ! -d "$TEMP_DIR/shapes" ]]; then
        print_warning "Failed to clone shapes repository (exit code: $shapes_exit_code) - shapes import will be skipped"
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

check_frontend_changes() {
    print_step "Checking for frontend changes"
    
    local frontend_paths=(
        "frontend/"
        "package.json"
        "package-lock.json"
        "vite.config.ts"
        "tsconfig.json"
        "tailwind.config.js"
        ".env.example"
    )
    
    local install_dir_repo="$INSTALL_DIR"
    local hash_cache_file="$CONFIG_CACHE/frontend-hash.txt"
    
    # Default to true for safety (build if we can't determine changes)
    FRONTEND_CHANGED=true
    
    # Create cache directory if it doesn't exist
    mkdir -p "$CONFIG_CACHE"
    
    # If this is a fresh installation (no existing installation), always build
    if [[ ! -d "$install_dir_repo" ]]; then
        print_step "Fresh installation detected - frontend build required"
        log "No existing installation found, will build frontend"
        return 0
    fi
    
    # Check if we have a cached hash from previous installation
    if [[ ! -f "$hash_cache_file" ]]; then
        print_step "No previous frontend hash found - frontend build required"
        log "No cached frontend hash found, will build frontend"
        return 0
    fi
    
    # Read the previous hash
    local previous_hash
    if ! previous_hash="$(cat "$hash_cache_file" 2>/dev/null)"; then
        print_step "Could not read previous hash - frontend build required"
        log "Failed to read cached frontend hash, will build frontend"
        return 0
    fi
    
    # Calculate current hash of frontend-related files in the new repository
    local current_hash
    cd "$TEMP_DIR/iamgickpro"
    
    # Create a combined hash of all frontend-related files
    if ! current_hash="$(git rev-parse HEAD 2>/dev/null && \
                        find frontend/ -name "*.vue" -o -name "*.ts" -o -name "*.js" -o -name "*.json" -o -name "*.css" 2>/dev/null | \
                        sort | xargs -I {} sh -c 'echo "{}:$(git log -1 --format="%H" -- "{}" 2>/dev/null || echo "new")"' | \
                        sha256sum | cut -d' ' -f1)"; then
        print_step "Could not calculate current hash - frontend build required"
        log "Failed to calculate current frontend hash, will build frontend"
        return 0
    fi
    
    # Compare hashes
    if [[ "$previous_hash" == "$current_hash" ]]; then
        print_success "Frontend unchanged since last installation - build can be skipped"
        FRONTEND_CHANGED=false
        log "Frontend hash match: $current_hash - skipping build"
    else
        print_step "Frontend changes detected - build required"
        log "Frontend hash changed: $previous_hash -> $current_hash - will build"
        
        # Update the hash cache with the new hash
        echo "$current_hash" > "$hash_cache_file"
    fi
    
    cd - > /dev/null
}

update_frontend_hash() {
    print_step "Updating frontend hash cache"
    
    local hash_cache_file="$CONFIG_CACHE/frontend-hash.txt"
    
    # Create cache directory if it doesn't exist
    mkdir -p "$CONFIG_CACHE"
    
    # Calculate and store the current frontend hash
    cd "$TEMP_DIR/iamgickpro"
    
    local current_hash
    if current_hash="$(git rev-parse HEAD 2>/dev/null && \
                       find frontend/ -name "*.vue" -o -name "*.ts" -o -name "*.js" -o -name "*.json" -o -name "*.css" 2>/dev/null | \
                       sort | xargs -I {} sh -c 'echo "{}:$(git log -1 --format="%H" -- "{}" 2>/dev/null || echo "new")"' | \
                       sha256sum | cut -d' ' -f1)"; then
        echo "$current_hash" > "$hash_cache_file"
        print_success "Frontend hash cached: $current_hash"
        log "Frontend hash updated in cache: $current_hash"
    else
        print_warning "Could not calculate frontend hash for caching"
        log_warning "Failed to calculate frontend hash for caching"
    fi
    
    cd - > /dev/null
}

# Main repository cloning function
clone_repositories() {
    # Ensure clean temporary directory
    print_step "Preparing clean workspace"
    
    # Remove any existing repository directories
    rm -rf "$TEMP_DIR/iamgickpro" "$TEMP_DIR/shapes" 2>/dev/null || true
    
    # Ensure temp directory exists
    mkdir -p "$TEMP_DIR"
    
    clone_main_repository
    clone_shapes_repository
    verify_repository_structure
    
    # Check for frontend changes (affects whether we need to build)
    check_frontend_changes
    
    print_success "Repository cloning completed"
    
    if [[ "$FRONTEND_CHANGED" == "true" ]]; then
        log "Frontend build will be required in phase 6"
    else
        log "Frontend build will be skipped in phase 6"
    fi
}

# Execute repository cloning
clone_repositories
