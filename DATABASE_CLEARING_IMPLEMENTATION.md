# Database Clearing for Clean Reinstalls

## Problem
When reinstalling IAMGickPro and clearing the installation directory, the database might still contain records that reference files that no longer exist (e.g., uploaded files, templates, media). This can cause:
- Broken file references
- 404 errors for missing files  
- Inconsistent application state
- Poor user experience

## Solution
Added intelligent database clearing logic that:

1. **Automatic Clearing**: When force reinstall or manual directory clearing is chosen, the installer sets a `CLEAR_DATABASE=true` flag
2. **Smart Detection**: Database setup phase detects mismatched state (fresh directory + existing database)
3. **User Choice**: Prompts user for action when database exists but installation is fresh

## Implementation

### In `install.sh`
Added `export CLEAR_DATABASE=true` in two locations:
- Force reinstall mode (line ~423)
- Interactive backup and proceed option (line ~446)

### In `phases/07-database-setup.sh`
Added logic to:
1. Check `CLEAR_DATABASE` flag and automatically drop/recreate database
2. Detect fresh installation with existing database
3. Prompt user for appropriate action

## User Experience

### Force Reinstall
```bash
sudo ./install.sh --force-reinstall
```
- Automatically clears both directory and database
- No user prompts needed
- Clean slate installation

### Interactive Reinstall
When directory exists and user chooses "Backup and proceed":
- Directory is cleared
- Database is automatically cleared
- Consistent fresh installation

### Mixed State Detection
When fresh installation detects existing database:
```
Database exists but installation directory is fresh
Options:
1) Keep existing database (may have orphaned file references)
2) Clear database for fresh start (recommended for clean install)  
3) Exit and handle manually
```

## Benefits
- **Data Consistency**: Ensures files and database records match
- **Clean Installs**: No orphaned references from previous installations
- **User Control**: Clear options when state mismatch is detected
- **Safety**: Backups are created before any destructive operations
- **Flexibility**: Manual option for complex scenarios

## Files Modified
- `/iamgickpro-installer/install.sh`: Added CLEAR_DATABASE flag setting
- `/iamgickpro-installer/phases/07-database-setup.sh`: Added database clearing logic
