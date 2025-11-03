# TFSwitcher - Terraform Version Manager for Windows

A PowerShell module for managing and switching between multiple Terraform versions on Windows, with support for both online and offline/air-gapped environments.

## Features

- **Auto-detection**: Automatically detects Terraform installation or uses configurable paths
- **Version Management**: Download, install, and switch between Terraform versions
- **Offline Mode**: Full support for air-gapped environments with local Terraform binaries
- **Environment Variables**: Configure offline mode and source path via environment variables for persistence across sessions
- **Smart Version Resolution**: Supports full versions (1.5.7), major.minor patterns (1.5 for latest 1.5.x), or `-Latest` flag
- **Auto-switching**: Automatically switches to newly downloaded/imported versions
- **Easy Rollback**: Undo functionality to revert to the previous version
- **Configurable Paths**: Customize installation directories to fit your workflow
- **No Manual PATH Management**: Works with your existing Terraform PATH configuration
- **Multiple Import Options**: Import from zip files, directories, or individual executables

## Requirements

- PowerShell 5.1 or later
- Windows OS
- Internet connection for downloading Terraform versions (not required in offline mode)

## Installation

### Method 1: Manual Installation (Recommended)

1. Clone or download this repository:

   ```powershell
   git clone https://github.com/jpmicrosoft/tfswitcher.git
   ```

2. Import the module in your PowerShell session:

   ```powershell
   Import-Module "C:\path\to\tfswitcher\tfswitcher.psd1"
   ```

3. **(Optional)** Add to your PowerShell profile for automatic loading:

   Open your profile:

   ```powershell
   notepad $PROFILE
   ```

   Add this line (adjust the path to where you cloned the repository):

   ```powershell
   Import-Module "C:\path\to\tfswitcher\tfswitcher.psd1"
   ```

### Method 2: Install to PowerShell Modules Directory

1. Copy the module to your PowerShell modules directory:

   ```powershell
   $modulePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\tfswitcher"
   New-Item -Path $modulePath -ItemType Directory -Force
   Copy-Item -Path "C:\path\to\tfswitcher\*" -Destination $modulePath -Recurse
   ```

2. Import the module:

   ```powershell
   Import-Module tfswitcher
   ```

3. **(Optional)** Add to your profile for automatic loading:

   ```powershell
   notepad $PROFILE
   # Add this line:
   Import-Module tfswitcher
   ```

### Verify Installation

After importing, verify the module is loaded:

```powershell
Get-Module tfswitcher
```

## Configuration

On first run, TFSwitcher will automatically:

- Create a directory at `%LOCALAPPDATA%\tfswitcher` for storing Terraform versions
- Detect your existing Terraform installation in PATH, or create `%LOCALAPPDATA%\terraform` as the active Terraform directory

To view or modify configuration:

```powershell
tfswitcher -Config
```

### Configuration Options

- **Terraform Path**: Location of the active terraform.exe
- **TFSwitcher Path**: Location where downloaded versions are stored
- **Offline Mode**: Enable/disable offline mode for air-gapped environments
- **Offline Source Path**: Directory containing local Terraform binaries for offline mode

### Environment Variables

TFSwitcher supports environment variables for persistent configuration:

- **`TFSWITCHER_OFFLINE_MODE`**: Set to `true`, `1`, `yes`, or `on` to enable offline mode automatically
- **`TFSWITCHER_OFFLINE_SOURCE`**: Path to the directory containing offline Terraform binaries

These variables are checked when the module loads and can be set permanently during configuration.

**Setting environment variables manually:**

```powershell
# Enable offline mode for all future sessions
[System.Environment]::SetEnvironmentVariable('TFSWITCHER_OFFLINE_MODE', 'true', 'User')

# Set offline source path for all future sessions
[System.Environment]::SetEnvironmentVariable('TFSWITCHER_OFFLINE_SOURCE', 'C:\TerraformBinaries', 'User')
```

## Usage

### Display Help

```powershell
tfswitcher -Help
```

### Online Mode (Default)

#### Download Terraform Versions

Download a specific version (automatically switches to it after download):

```powershell
tfswitcher -Download
# Then enter: 1.5.7
```

Download the latest patch version of a major.minor release:

```powershell
tfswitcher -Download
# Then enter: 1.5  (automatically finds latest 1.5.x)
```

Download the absolute latest version:

```powershell
tfswitcher -Download -Latest
```

**Note**: After downloading, TFSwitcher will automatically switch to the newly downloaded version and back up your previous version.

### Offline Mode

#### Configure Offline Mode

1. Enable offline mode and set the source path:

```powershell
tfswitcher -Config
# Answer the prompts:
# - Enable offline mode: y
# - Enter offline source path: C:\TerraformBinaries
# - Save offline mode setting to environment variable: y (recommended)
# - Save offline source path to environment variable: y (recommended)
```

**Note**: Saving to environment variables ensures the settings persist across PowerShell sessions.

2. List available versions in your offline source:

```powershell
tfswitcher -ListOffline
```

#### Supported Offline File Formats

Place your Terraform binaries in the offline source directory using any of these formats:

- **Zip files**: `terraform_1.5.7_windows_amd64.zip`
- **Version folders**: `1.5.7\terraform.exe`
- **Standalone executables**: `terraform.exe` (version auto-detected)

#### Import from Offline Source

Import a specific version (automatically switches to it after import):

```powershell
tfswitcher -Download
# Then enter: 1.5.7
```

Import the latest version available in offline source:

```powershell
tfswitcher -Download -Latest
```

**Note**: In offline mode, `-Download` imports from your configured offline source path instead of downloading from HashiCorp. The version is automatically activated after import.

#### Manual Import

You can also manually import specific files:

```powershell
# Import from a zip file
tfswitcher -Import -Path "C:\Downloads\terraform_1.5.7_windows_amd64.zip"

# Import from a directory
tfswitcher -Import -Path "C:\terraform-binaries\1.5.7"

# Import a standalone executable
tfswitcher -Import -Path "C:\tools\terraform.exe"

# Specify version manually
tfswitcher -Import -Path "C:\Downloads\terraform.exe" -Version "1.5.7"
```

**Note**: After importing, you'll be prompted to switch to the imported version immediately (y/n).

### List Downloaded Versions

View all locally imported Terraform versions:

```powershell
tfswitcher -ListVersions
```

View available versions in offline source (offline mode only):

```powershell
tfswitcher -ListOffline
```

### Switch Terraform Version

Switch to a different version (must be previously downloaded/imported):

```powershell
tfswitcher -SwitchVersion
# Then enter the version number
```

### Undo Last Switch

Revert to the previous Terraform version:

```powershell
tfswitcher -Undo
```

### View/Change Configuration

View or modify the Terraform paths and offline mode settings:

```powershell
tfswitcher -Config
```

## How It Works

1. **Storage**: Downloaded/imported Terraform versions are stored in `%LOCALAPPDATA%\tfswitcher\<version>\`
2. **Active Version**: The active `terraform.exe` is located in your Terraform PATH directory (detected automatically or configured manually)
3. **Switching**: When switching versions, TFSwitcher:
   - Backs up the current `terraform.exe` to the `previous` folder
   - Copies the requested version to the active Terraform directory
4. **Undo**: Restores the backed-up version from the `previous` folder
5. **Offline Mode**: When enabled, `-Download` command imports from the configured offline source directory instead of downloading from HashiCorp
6. **Auto-Switching**: After downloading or importing, TFSwitcher automatically switches to the new version and backs up the previous one

## Examples

### Online Workflow Example

```powershell
# 1. Import the module (if not in profile)
Import-Module tfswitcher

# 2. Download Terraform 1.5.7 from HashiCorp (auto-switches to it)
tfswitcher -Download
# Enter: 1.5.7

# 3. Download the latest 1.6.x version (auto-switches to it)
tfswitcher -Download
# Enter: 1.6

# 4. List all downloaded versions
tfswitcher -ListVersions

# 5. Switch to version 1.5.7
tfswitcher -SwitchVersion
# Enter: 1.5.7

# 6. Verify the version
terraform version

# 7. Undo the switch (back to previous version)
tfswitcher -Undo

# 8. Verify the version again
terraform version
```

### Offline/Air-Gapped Workflow Example

```powershell
# 1. Import the module
Import-Module tfswitcher

# 2. Configure offline mode with persistence
tfswitcher -Config
# - Enable offline mode: y
# - Set offline source path: C:\TerraformBinaries
# - Save offline mode setting to environment variable: y
# - Save offline source path to environment variable: y

# 3. Check what's available in your offline source
tfswitcher -ListOffline

# 4. Import the latest version from offline source (auto-switches)
tfswitcher -Download -Latest

# 5. Import a specific version (auto-switches)
tfswitcher -Download
# Enter: 1.5.7

# 6. List all imported versions
tfswitcher -ListVersions

# 7. Switch between versions
tfswitcher -SwitchVersion
# Enter: 1.5.7

# 8. Verify the version
terraform version
```

### Using Environment Variables

```powershell
# Set environment variables (one-time setup)
[System.Environment]::SetEnvironmentVariable('TFSWITCHER_OFFLINE_MODE', 'true', 'User')
[System.Environment]::SetEnvironmentVariable('TFSWITCHER_OFFLINE_SOURCE', 'C:\TerraformBinaries', 'User')

# Restart PowerShell or reload environment
# Now offline mode is automatically enabled
Import-Module tfswitcher

# The module will show:
# "Offline mode enabled via environment variable."
# "Using offline source path from environment variable: C:\TerraformBinaries"

# Import directly without configuration
tfswitcher -Download -Latest
```

### Preparing Binaries for Offline Use

On a machine with internet access:

```powershell
# Download Terraform binaries from HashiCorp
# https://releases.hashicorp.com/terraform/

# Save to a directory with one of these structures:
# Option 1: Keep the original zip files
C:\TerraformBinaries\
  ├── terraform_1.5.7_windows_amd64.zip
  ├── terraform_1.6.0_windows_amd64.zip
  └── terraform_1.6.1_windows_amd64.zip

# Option 2: Extract into version folders
C:\TerraformBinaries\
  ├── 1.5.7\
  │   └── terraform.exe
  ├── 1.6.0\
  │   └── terraform.exe
  └── 1.6.1\
      └── terraform.exe

# Transfer this directory to your offline machine
```

## Troubleshooting

### PATH Not Set

If Terraform is not in your PATH, TFSwitcher will create a directory at `%LOCALAPPDATA%\terraform` and display instructions to add it to your PATH:

**For current session only:**

```powershell
$env:Path += ";$env:LOCALAPPDATA\terraform"
```

**Permanently (User level):**

```powershell
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$env:LOCALAPPDATA\terraform", [EnvironmentVariableTarget]::User)
```

### Offline Mode: No Versions Found

If `tfswitcher -ListOffline` shows no versions:

1. Verify the offline source path is correct: `tfswitcher -Config`
2. Check that files are in a supported format:
   - `terraform_X.X.X_windows_*.zip`
   - `X.X.X\terraform.exe`
   - `terraform.exe` (will auto-detect version)
3. Ensure the directory exists and is accessible

### Environment Variable Not Working

If environment variables aren't being recognized:

1. Verify they're set:
   ```powershell
   $env:TFSWITCHER_OFFLINE_MODE
   $env:TFSWITCHER_OFFLINE_SOURCE
   ```

2. Restart PowerShell to load user-level environment variables

3. Check for typos in variable names (they're case-insensitive but must match exactly)

### Session-Only Configuration Changes

When you decline to save configuration changes to environment variables, they only apply to the current PowerShell session. If you have environment variables set, they will override session-only changes when you start a new PowerShell session.

### Security Warning / Execution Policy

If you encounter security warnings about running scripts, you may need to:

1. **Unblock the downloaded files:**

   ```powershell
   Get-ChildItem -Path "C:\path\to\tfswitcher" -Recurse | Unblock-File
   ```

2. **Or adjust your execution policy (if permitted):**

   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

### Module Not Found

If PowerShell can't find the module:

```powershell
# Check your module path
$env:PSModulePath -split ';'

# Verify the module location
Get-Module -ListAvailable tfswitcher
```

## Migration from Previous Version

If you were using the old function-based version of tfswitcher:

1. Remove the old function loading code from your PowerShell profile
2. Install the new module using the instructions above
3. Your existing downloaded versions in the tfswitcher folder will continue to work

## Command Reference

| Command | Description |
|---------|-------------|
| `tfswitcher -Download` | Download/import a Terraform version (online or offline); auto-switches to it |
| `tfswitcher -Download -Latest` | Download/import the latest available version; auto-switches to it |
| `tfswitcher -Import -Path <path>` | Manually import a specific Terraform binary; prompts to switch |
| `tfswitcher -ListVersions` | List all locally imported versions |
| `tfswitcher -ListOffline` | List available versions in offline source |
| `tfswitcher -SwitchVersion` | Switch to a different version |
| `tfswitcher -Undo` | Revert to previous version |
| `tfswitcher -Config` | View/change configuration (includes environment variable persistence) |
| `tfswitcher -Help` | Display help information |

## License

See [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Repository

GitHub: [https://github.com/jpmicrosoft/tfswitcher](https://github.com/jpmicrosoft/tfswitcher)