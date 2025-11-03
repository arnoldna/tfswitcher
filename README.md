# TFSwitcher - Terraform Version Manager for Windows

A PowerShell module for managing and switching between multiple Terraform versions on Windows.

## Features

- **Auto-detection**: Automatically detects Terraform installation or uses configurable paths
- **Version Management**: Download, install, and switch between Terraform versions
- **Smart Version Resolution**: Supports full versions (1.5.7), major.minor patterns (1.5 for latest 1.5.x), or `-Latest` flag
- **Easy Rollback**: Undo functionality to revert to the previous version
- **Configurable Paths**: Customize installation directories to fit your workflow
- **No Manual PATH Management**: Works with your existing Terraform PATH configuration

## Requirements

- PowerShell 5.1 or later
- Windows OS
- Internet connection for downloading Terraform versions

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

## Usage

### Display Help

```powershell
tfswitcher -Help
```

### Download Terraform Versions

Download a specific version:

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

### List Downloaded Versions

View all locally available Terraform versions:

```powershell
tfswitcher -ListVersions
```

### Switch Terraform Version

Switch to a different version (must be previously downloaded):

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

View or modify the Terraform and TFSwitcher paths:

```powershell
tfswitcher -Config
```

## How It Works

1. **Storage**: Downloaded Terraform versions are stored in `%LOCALAPPDATA%\tfswitcher\<version>\`
2. **Active Version**: The active `terraform.exe` is located in your Terraform PATH directory (detected automatically or configured manually)
3. **Switching**: When switching versions, TFSwitcher:
   - Backs up the current `terraform.exe` to the `previous` folder
   - Copies the requested version to the active Terraform directory
4. **Undo**: Restores the backed-up version from the `previous` folder

## Examples

### Complete Workflow Example

```powershell
# 1. Import the module (if not in profile)
Import-Module tfswitcher

# 2. Download Terraform 1.5.7
tfswitcher -Download
# Enter: 1.5.7

# 3. Download the latest 1.6.x version
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

## License

See [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Repository

GitHub: [https://github.com/jpmicrosoft/tfswitcher](https://github.com/jpmicrosoft/tfswitcher)
