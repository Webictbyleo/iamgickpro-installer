#!/bin/bash

# Phase 9: Media Dependencies
# Compiles and installs ImageMagick and FFmpeg from source

install_media_dependencies() {
    print_step "Installing media processing dependencies"
    
    local build_dir="/tmp/media-build"
    mkdir -p "$build_dir"
    
    # Install build dependencies
    print_step "Installing build dependencies"
    
    apt-get install -y \
        build-essential \
        cmake \
        pkg-config \
        libtool \
        autoconf \
        automake \
        yasm \
        nasm \
        libx264-dev \
        libx265-dev \
        libvpx-dev \
        libfdk-aac-dev \
        libmp3lame-dev \
        libopus-dev \
        libvorbis-dev \
        libtheora-dev \
        libwebp-dev \
        libjpeg-dev \
        libpng-dev \
        libtiff-dev \
        libgif-dev \
        zlib1g-dev \
        libbz2-dev \
        libfreetype6-dev \
        libfontconfig1-dev \
        libxml2-dev \
        libgomp1 \
        librsvg2-dev \
        libcairo2-dev \
        libpango1.0-dev \
        wget \
        curl
    
    print_success "Build dependencies installed"
    
    if [[ "$INSTALL_IMAGEMAGICK" == "true" ]]; then
        install_imagemagick "$build_dir"
    fi
    
    if [[ "$INSTALL_FFMPEG" == "true" ]]; then
        install_ffmpeg "$build_dir"
    fi
    
    # Cleanup build directory
    print_step "Cleaning up build files"
    rm -rf "$build_dir"
    print_success "Build cleanup completed"
    
    print_success "Media dependencies installation completed"
}

install_imagemagick() {
    local build_dir="$1"
    
    print_step "Installing ImageMagick from source"
    
    # Check if ImageMagick is already installed with required features
    if command -v convert &> /dev/null; then
        local current_version=$(convert -version | head -n1 | awk '{print $3}' | cut -d'.' -f1 2>/dev/null || echo "0")
        
        # Check for required features
        local has_svg=false
        local has_webp=false
        local has_jpeg=false
        local has_png=false
        local version_ok=false
        
        # Validate version is numeric and check if >= 7
        if [[ "$current_version" =~ ^[0-9]+$ ]] && [[ "$current_version" -ge 7 ]]; then
            version_ok=true
        fi
        
        # Check for SVG support
        if convert -list format | grep -q "SVG.*rw"; then
            has_svg=true
        fi
        
        # Check for WebP support
        if convert -list format | grep -q "WEBP.*rw"; then
            has_webp=true
        fi
        
        # Check for JPEG support
        if convert -list format | grep -q "JPEG.*rw"; then
            has_jpeg=true
        fi
        
        # Check for PNG support
        if convert -list format | grep -q "PNG.*rw"; then
            has_png=true
        fi
        
        if [[ "$version_ok" == true ]] && [[ "$has_svg" == true ]] && [[ "$has_webp" == true ]] && [[ "$has_jpeg" == true ]] && [[ "$has_png" == true ]]; then
            local full_version=$(convert -version | head -n1 | awk '{print $3}')
            print_success "ImageMagick $full_version with required features (SVG, WebP, JPEG, PNG) already installed - skipping compilation"
            return 0
        else
            local missing_features=""
            [[ "$version_ok" == false ]] && missing_features+="version<7 "
            [[ "$has_svg" == false ]] && missing_features+="SVG "
            [[ "$has_webp" == false ]] && missing_features+="WebP "
            [[ "$has_jpeg" == false ]] && missing_features+="JPEG "
            [[ "$has_png" == false ]] && missing_features+="PNG "
            print_step "ImageMagick found but missing features: $missing_features- will reinstall"
        fi
    fi
    
    cd "$build_dir"
    
    # Download latest ImageMagick source
    print_step "Downloading ImageMagick source"
    
    # Get the latest release from GitHub API
    IMAGEMAGICK_VERSION=$(curl -s https://api.github.com/repos/ImageMagick/ImageMagick/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    
    if [[ -z "$IMAGEMAGICK_VERSION" ]]; then
        # Fallback to a known working version
        IMAGEMAGICK_VERSION="7.1.1-29"
        print_warning "Could not fetch latest version, using fallback: $IMAGEMAGICK_VERSION"
    else
        print_success "Using latest ImageMagick version: $IMAGEMAGICK_VERSION"
    fi
    
    wget -q "https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${IMAGEMAGICK_VERSION}.tar.gz" -O imagemagick.tar.gz
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to download ImageMagick source"
        return 1
    fi
    
    tar xzf imagemagick.tar.gz
    cd "ImageMagick-${IMAGEMAGICK_VERSION}"
    
    # Configure ImageMagick build
    print_step "Configuring ImageMagick build"
    
    ./configure \
        --prefix=/usr/local \
        --enable-shared \
        --enable-static \
        --with-modules \
        --with-quantum-depth=16 \
        --with-magick-plus-plus \
        --with-perl \
        --without-x \
        --disable-openmp \
        --with-jpeg \
        --with-png \
        --with-tiff \
        --with-webp \
        --with-freetype \
        --with-fontconfig \
        --with-xml \
        --with-rsvg \
        --with-cairo \
        --with-pango \
        --enable-hdri &> /dev/null
    
    if [[ $? -ne 0 ]]; then
        print_error "ImageMagick configuration failed"
        return 1
    fi
    
    # Compile ImageMagick
    print_step "Compiling ImageMagick (this may take several minutes)"
    
    local cpu_cores=$(nproc)
    make -j"$cpu_cores" &
    spinner
    wait $!
    
    if [[ $? -ne 0 ]]; then
        print_error "ImageMagick compilation failed"
        return 1
    fi
    
    # Install ImageMagick
    print_step "Installing ImageMagick"
    
    make install &
    spinner
    wait $!
    
    if [[ $? -ne 0 ]]; then
        print_error "ImageMagick installation failed"
        return 1
    fi
    
    # Update library cache
    ldconfig
    
    # Verify installation
    if command -v convert &> /dev/null; then
        IMAGEMAGICK_INSTALLED_VERSION=$(convert -version | head -n1 | awk '{print $3}')
        print_success "ImageMagick $IMAGEMAGICK_INSTALLED_VERSION installed successfully"
    else
        print_error "ImageMagick installation verification failed"
        return 1
    fi
    
    # Create ImageMagick policy for web applications
    print_step "Configuring ImageMagick security policy"
    
    # Get system resources
    TOTAL_MEMORY=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    MEMORY_LIMIT=$(($TOTAL_MEMORY / 4))  # Use 1/4 of system memory
    MAP_LIMIT=$(($TOTAL_MEMORY / 2))     # Use 1/2 of system memory for map
    DISK_LIMIT="2GiB"                    # Fixed disk limit
    CPU_CORES=$(nproc)
    THREAD_LIMIT=$((CPU_CORES * 2))      # 2 threads per core
    
    mkdir -p /usr/local/etc/ImageMagick-7
    
    cat > /usr/local/etc/ImageMagick-7/policy.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policymap [
<!ELEMENT policymap (policy)+>
<!ELEMENT policy (#PCDATA)>
<!ATTLIST policy domain (delegate|coder|filter|path|resource) #IMPLIED>
<!ATTLIST policy name CDATA #IMPLIED>
<!ATTLIST policy pattern CDATA #IMPLIED>
<!ATTLIST policy rights CDATA #IMPLIED>
<!ATTLIST policy stealth (True|False) "False">
<!ATTLIST policy value CDATA #IMPLIED>
]>
<policymap>
  <!-- Resource limits based on system specifications -->
  <policy domain="resource" name="temporary-path" value="/tmp"/>
  <policy domain="resource" name="memory" value="${MEMORY_LIMIT}MiB"/>
  <policy domain="resource" name="map" value="${MAP_LIMIT}MiB"/>
  <policy domain="resource" name="width" value="32KP"/>
  <policy domain="resource" name="height" value="32KP"/>
  <policy domain="resource" name="area" value="1GB"/>
  <policy domain="resource" name="disk" value="$DISK_LIMIT"/>
  <policy domain="resource" name="file" value="1024"/>
  <policy domain="resource" name="thread" value="$THREAD_LIMIT"/>
  <policy domain="resource" name="throttle" value="0"/>
  <policy domain="resource" name="time" value="300"/>
  
  <!-- Disable potentially dangerous coders -->
  <policy domain="coder" rights="none" pattern="PS" />
  <policy domain="coder" rights="none" pattern="PS2" />
  <policy domain="coder" rights="none" pattern="PS3" />
  <policy domain="coder" rights="none" pattern="EPS" />
  <policy domain="coder" rights="none" pattern="PDF" />
  <policy domain="coder" rights="none" pattern="XPS" />
  
  <!-- Allow common web formats -->
  <policy domain="coder" rights="read|write" pattern="JPEG" />
  <policy domain="coder" rights="read|write" pattern="PNG" />
  <policy domain="coder" rights="read|write" pattern="GIF" />
  <policy domain="coder" rights="read|write" pattern="WEBP" />
  <policy domain="coder" rights="read|write" pattern="SVG" />
  <policy domain="coder" rights="read|write" pattern="TIFF" />
</policymap>
EOF

    print_success "ImageMagick security policy configured for ${TOTAL_MEMORY}MB system"
}

install_ffmpeg() {
    local build_dir="$1"
    
    print_step "Installing FFmpeg from source"
    
    # Check if FFmpeg is already installed with required features
    if command -v ffmpeg &> /dev/null; then
        local ffmpeg_info=$(ffmpeg -version 2>&1)
        local version_line=$(echo "$ffmpeg_info" | head -n1)
        local has_required_libs=true
        
        # Check for required libraries in the version output
        local required_libs=("libx264" "libx265" "libvpx" "libwebp" "libmp3lame" "libopus" "libvorbis")
        local missing_libs=""
        
        for lib in "${required_libs[@]}"; do
            if ! echo "$ffmpeg_info" | grep -q "$lib"; then
                has_required_libs=false
                missing_libs+="$lib "
            fi
        done
        
        # Also check if it's a recent build (has libavutil version >= 58)
        local libavutil_version=$(echo "$ffmpeg_info" | grep "libavutil" | awk '{print $2}' | cut -d'.' -f1)
        local version_ok=false
        
        if [[ "$libavutil_version" =~ ^[0-9]+$ ]] && [[ "$libavutil_version" -ge 58 ]]; then
            version_ok=true
        fi
        
        if [[ "$has_required_libs" == true ]] && [[ "$version_ok" == true ]]; then
            local version_display=$(echo "$version_line" | awk '{print $3}')
            print_success "FFmpeg $version_display with required libraries already installed - skipping compilation"
            return 0
        else
            local issues=""
            [[ "$version_ok" == false ]] && issues+="old_version "
            [[ "$has_required_libs" == false ]] && issues+="missing_libs($missing_libs) "
            print_step "FFmpeg found but has issues: $issues- will reinstall"
        fi
    fi
    
    cd "$build_dir"
    
    # Download latest FFmpeg source
    print_step "Downloading FFmpeg source"
    
    # Use the reliable snapshot source
    print_step "Using FFmpeg snapshot from ffmpeg.org"
    
    wget -q "http://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2" -O ffmpeg-snapshot.tar.bz2
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to download FFmpeg source"
        return 1
    fi
    
    tar xf ffmpeg-snapshot.tar.bz2
    cd ffmpeg
    
    # Configure FFmpeg build
    print_step "Configuring FFmpeg build"
    
    ./configure \
        --prefix=/usr/local \
        --enable-shared \
        --enable-static \
        --enable-gpl \
        --enable-version3 \
        --enable-nonfree \
        --disable-debug \
        --disable-doc \
        --enable-libx264 \
        --enable-libx265 \
        --enable-libvpx \
        --enable-libfdk-aac \
        --enable-libmp3lame \
        --enable-libopus \
        --enable-libvorbis \
        --enable-libtheora \
        --enable-libwebp \
        --enable-pic \
        --extra-libs=-lpthread \
        --extra-libs=-lm
    
    if [[ $? -ne 0 ]]; then
        print_error "FFmpeg configuration failed"
        return 1
    fi
    
    # Compile FFmpeg
    print_step "Compiling FFmpeg (this may take 10-15 minutes)"
    
    local cpu_cores=$(nproc)
    make -j"$cpu_cores" &
    spinner
    wait $!
    
    if [[ $? -ne 0 ]]; then
        print_error "FFmpeg compilation failed"
        return 1
    fi
    
    # Install FFmpeg
    print_step "Installing FFmpeg"
    
    make install &
    spinner
    wait $!
    
    if [[ $? -ne 0 ]]; then
        print_error "FFmpeg installation failed"
        return 1
    fi
    
    # Update library cache
    ldconfig
    
    # Verify installation
    if command -v ffmpeg &> /dev/null; then
        FFMPEG_INSTALLED_VERSION=$(ffmpeg -version 2>&1 | head -n1 | awk '{print $3}')
        print_success "FFmpeg $FFMPEG_INSTALLED_VERSION installed successfully from snapshot"
    else
        print_error "FFmpeg installation verification failed"
        return 1
    fi
}

# Run the installation
install_media_dependencies
