#!/bin/bash

# iCloud Dotfiles Sync Script
# This script syncs .zshrc, .zsh_sessions, and .zsh_history with iCloud Drive

set -e  # Exit on any error

# Define paths
ICLOUD_DOTFILES="$HOME/Library/Mobile Documents/com~apple~CloudDocs/dotfiles"
HOME_DIR="$HOME"

# Files to sync
FILES=(".zshrc" ".zsh_sessions" ".zsh_history")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if iCloud Drive is available
check_icloud() {
    if [ ! -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]; then
        print_error "iCloud Drive not found. Please ensure iCloud Drive is enabled."
        exit 1
    fi
}

# Function to create iCloud dotfiles directory
create_dotfiles_dir() {
    if [ ! -d "$ICLOUD_DOTFILES" ]; then
        print_status "Creating iCloud dotfiles directory..."
        mkdir -p "$ICLOUD_DOTFILES"
        print_success "Created directory: $ICLOUD_DOTFILES"
    else
        print_status "iCloud dotfiles directory already exists"
    fi
}

# Function to handle file migration and symlinking
process_file() {
    local file="$1"
    local home_file="$HOME_DIR/$file"
    local icloud_file="$ICLOUD_DOTFILES/$file"
    
    print_status "Processing $file..."
    
    # Check if file exists in iCloud dotfiles
    if [ ! -e "$icloud_file" ]; then
        # iCloud file doesn't exist
        if [ -e "$home_file" ]; then
            # Home file exists, move it to iCloud
            if [ -L "$home_file" ]; then
                print_warning "$home_file is already a symlink, removing it"
                rm "$home_file"
            else
                print_status "Moving $home_file to iCloud dotfiles..."
                mv "$home_file" "$icloud_file"
                print_success "Moved $file to iCloud dotfiles"
            fi
        else
            # Neither file exists, create empty file in iCloud
            print_status "Creating new empty $file in iCloud dotfiles..."
            touch "$icloud_file"
            print_success "Created empty $file in iCloud dotfiles"
        fi
    else
        # iCloud file exists
        if [ -e "$home_file" ]; then
            if [ -L "$home_file" ]; then
                # Home file is already a symlink
                local link_target=$(readlink "$home_file")
                if [ "$link_target" = "$icloud_file" ]; then
                    print_status "$file symlink already exists and points to correct location"
                    return
                else
                    print_warning "$file symlink exists but points to wrong location, fixing..."
                    rm "$home_file"
                fi
            else
                # Home file exists but is not a symlink, remove it
                print_warning "$file exists in home directory, removing to prepare for symlink..."
                rm -rf "$home_file"
                print_success "Removed $file from home directory"
            fi
        fi
    fi
    
    # Create symlink if it doesn't exist
    if [ ! -L "$home_file" ]; then
        print_status "Creating symlink for $file..."
        ln -s "$icloud_file" "$home_file"
        print_success "Created symlink: $home_file -> $icloud_file"
    fi
}

# Main execution
main() {
    echo "========================================"
    echo "   iCloud Dotfiles Sync Script"
    echo "========================================"
    echo
    
    print_status "Starting dotfiles sync process..."
    
    # Check if iCloud Drive is available
    check_icloud
    
    # Create dotfiles directory in iCloud Drive
    create_dotfiles_dir
    
    # Process each file
    for file in "${FILES[@]}"; do
        process_file "$file"
        echo
    done
    
    print_success "Dotfiles sync completed successfully!"
    echo
    print_status "Your dotfiles are now synced with iCloud Drive at:"
    print_status "$ICLOUD_DOTFILES"
    echo
    print_warning "Note: Changes may take a few minutes to sync between devices"
    print_warning "Run this script on each Mac where you want synced dotfiles"
}

# Run main function
main