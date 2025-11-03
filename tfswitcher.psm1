# Auto-detect or use configurable paths
$script:config = @{
    TerraformPath     = $null
    TFSwitcherPath    = $null
    OfflineMode       = $false  # Can be set via environment variable TFSWITCHER_OFFLINE_MODE
    OfflineSourcePath = $null  # Can be set via environment variable TFSWITCHER_OFFLINE_SOURCE
}

function Initialize-TFSwitcherPaths {
    # Use user's local AppData for tfswitcher path
    $script:config.TFSwitcherPath = Join-Path $env:LOCALAPPDATA "tfswitcher"

    # Create if doesn't exist
    if (-not (Test-Path $script:config.TFSwitcherPath)) {
        New-Item -Path $script:config.TFSwitcherPath -ItemType Directory -Force | Out-Null
        Write-Host "Created TFSwitcher directory at: $($script:config.TFSwitcherPath)" -ForegroundColor Cyan
    }

    # Try to find terraform in PATH
    $terraformInPath = (Get-Command terraform -ErrorAction SilentlyContinue).Source
    if ($terraformInPath) {
        $script:config.TerraformPath = Split-Path $terraformInPath -Parent
    }
    else {
        # Fallback: Use user's local AppData
        $script:config.TerraformPath = Join-Path $env:LOCALAPPDATA "terraform"

        # Create if doesn't exist
        if (-not (Test-Path $script:config.TerraformPath)) {
            New-Item -Path $script:config.TerraformPath -ItemType Directory -Force | Out-Null
            Write-Host "Created Terraform directory at: $($script:config.TerraformPath)" -ForegroundColor Cyan
        }
    }

    # Initialize offline mode from environment variable if available
    if ($env:TFSWITCHER_OFFLINE_MODE) {
        $offlineModeValue = $env:TFSWITCHER_OFFLINE_MODE.ToLower()
        if ($offlineModeValue -in @('true', '1', 'yes', 'on')) {
            $script:config.OfflineMode = $true
            Write-Host "Offline mode enabled via environment variable." -ForegroundColor Cyan
        }
        elseif ($offlineModeValue -in @('false', '0', 'no', 'off')) {
            $script:config.OfflineMode = $false
            Write-Host "Offline mode disabled via environment variable." -ForegroundColor Cyan
        }
    }

    # Initialize offline source path from environment variable if available
    if ($env:TFSWITCHER_OFFLINE_SOURCE) {
        $script:config.OfflineSourcePath = $env:TFSWITCHER_OFFLINE_SOURCE
        Write-Host "Using offline source path from environment variable: $($script:config.OfflineSourcePath)" -ForegroundColor Cyan
    }

    # Ensure previous folder exists
    $previousPath = Join-Path $script:config.TFSwitcherPath "previous"
    if (-not (Test-Path $previousPath)) {
        New-Item -Path $previousPath -ItemType Directory -Force | Out-Null
    }
}

# NEW FUNCTION: Scan and list available versions from offline source
function Get-OfflineVersions {
    param(
        [string]$SourcePath
    )

    if (-not $SourcePath) {
        $SourcePath = $script:config.OfflineSourcePath
    }

    if (-not $SourcePath -or -not (Test-Path $SourcePath)) {
        Write-Host "Error: Offline source path not configured or not found." -ForegroundColor Red
        Write-Host "Use 'tfswitcher -Config' to set the offline source path." -ForegroundColor Yellow
        return @()
    }

    $availableVersions = @()

    # Look for zip files matching terraform pattern
    $zipFiles = Get-ChildItem -Path $SourcePath -Filter "terraform_*.zip" -File -ErrorAction SilentlyContinue
    foreach ($zip in $zipFiles) {
        if ($zip.Name -match 'terraform_(\d+\.\d+\.\d+)_windows') {
            $availableVersions += [PSCustomObject]@{
                Version = $matches[1]
                Path    = $zip.FullName
                Type    = "Zip"
            }
        }
    }

    # Look for directories with version numbers containing terraform.exe
    $versionDirs = Get-ChildItem -Path $SourcePath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' }

    foreach ($dir in $versionDirs) {
        $exePath = Join-Path $dir.FullName "terraform.exe"
        if (Test-Path $exePath) {
            $availableVersions += [PSCustomObject]@{
                Version = $dir.Name
                Path    = $dir.FullName
                Type    = "Directory"
            }
        }
    }

    # Look for standalone terraform.exe files with version in parent directory name
    $exeFiles = Get-ChildItem -Path $SourcePath -Filter "terraform.exe" -File -Recurse -Depth 1 -ErrorAction SilentlyContinue
    foreach ($exe in $exeFiles) {
        $parentName = Split-Path $exe.DirectoryName -Leaf
        if ($parentName -match '^\d+\.\d+\.\d+$') {
            # Already covered by directory scan
            continue
        }

        # Try to detect version from the executable
        try {
            $versionOutput = & $exe.FullName -version 2>$null | Select-Object -First 1
            if ($versionOutput -match 'Terraform v(\d+\.\d+\.\d+)') {
                $detectedVersion = $matches[1]
                if ($availableVersions.Version -notcontains $detectedVersion) {
                    $availableVersions += [PSCustomObject]@{
                        Version = $detectedVersion
                        Path    = $exe.FullName
                        Type    = "Executable"
                    }
                }
            }
        }
        catch {
            # Skip if we can't detect version
        }
    }

    return $availableVersions | Sort-Object { [version]$_.Version } -Descending
}

# NEW FUNCTION: Import local Terraform binary
function Import-LocalTerraform {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$Version
    )

    # Validate the path exists
    if (-not (Test-Path $Path)) {
        Write-Host "Error: Path not found: $Path" -ForegroundColor Red
        return $false
    }

    # Check if it's a directory or file
    $item = Get-Item $Path

    if ($item.PSIsContainer) {
        # It's a directory - look for terraform.exe
        $exePath = Join-Path $Path "terraform.exe"
        if (-not (Test-Path $exePath)) {
            Write-Host "Error: terraform.exe not found in directory: $Path" -ForegroundColor Red
            return $false
        }
    }
    elseif ($item.Extension -eq ".zip") {
        # It's a zip file - extract it temporarily
        $tempExtract = Join-Path $env:TEMP "tfswitcher_temp_$([guid]::NewGuid())"
        New-Item -Path $tempExtract -ItemType Directory -Force | Out-Null

        try {
            Expand-Archive -Path $Path -DestinationPath $tempExtract -Force
            $exePath = Join-Path $tempExtract "terraform.exe"

            if (-not (Test-Path $exePath)) {
                Write-Host "Error: terraform.exe not found in zip file" -ForegroundColor Red
                Remove-Item $tempExtract -Recurse -Force
                return $false
            }
        }
        catch {
            Write-Host "Error extracting zip file: $_" -ForegroundColor Red
            if (Test-Path $tempExtract) {
                Remove-Item $tempExtract -Recurse -Force
            }
            return $false
        }
    }
    elseif ($item.Name -eq "terraform.exe") {
        # It's the executable directly
        $exePath = $Path
    }
    else {
        Write-Host "Error: Invalid file type. Expected terraform.exe or .zip file" -ForegroundColor Red
        return $false
    }

    # Get version from the binary if not specified
    if (-not $Version) {
        try {
            $versionOutput = & $exePath -version | Select-Object -First 1
            if ($versionOutput -match 'Terraform v(\d+\.\d+\.\d+)') {
                $Version = $matches[1]
                Write-Host "Detected version: $Version" -ForegroundColor Cyan
            }
            else {
                Write-Host "Could not detect version. Please specify with -Version parameter" -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "Error detecting version: $_" -ForegroundColor Red
            return $false
        }
    }

    # Check if version already exists
    $versionFolder = Join-Path $script:config.TFSwitcherPath $Version
    if (Test-Path $versionFolder) {
        Write-Host "Version $Version already exists." -ForegroundColor Yellow
        $overwrite = Read-Host -Prompt "Overwrite? (y/n)"
        if ($overwrite -ne 'y') {
            Write-Host "Import cancelled." -ForegroundColor Yellow
            if ($item.Extension -eq ".zip" -and (Test-Path $tempExtract)) {
                Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
            }
            return $false
        }
        Remove-Item $versionFolder -Recurse -Force
    }

    # Create version folder and copy executable
    New-Item -Path $versionFolder -ItemType Directory -Force | Out-Null
    Copy-Item -Path $exePath -Destination (Join-Path $versionFolder "terraform.exe") -Force

    Write-Host "Successfully imported Terraform $Version" -ForegroundColor Green

    # Clean up temp directory if we extracted a zip
    if ($item.Extension -eq ".zip" -and (Test-Path $tempExtract)) {
        Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }

    return $true
}

function Get-LatestTerraformVersion {
    param(
        [string]$MajorMinor
    )

    # NEW: Check if offline mode is enabled
    if ($script:config.OfflineMode) {
        Write-Host "Offline mode is enabled. Checking local versions..." -ForegroundColor Yellow

        $offlineVersions = Get-OfflineVersions
        if ($offlineVersions.Count -eq 0) {
            Write-Host "No versions found in offline source path." -ForegroundColor Red
            Write-Host "Configure offline source path with 'tfswitcher -Config'" -ForegroundColor Cyan
            return $null
        }

        if ($MajorMinor) {
            $filtered = $offlineVersions | Where-Object { $_.Version -like "$MajorMinor.*" } | Select-Object -First 1
            if ($filtered) {
                return $filtered.Version
            }
            else {
                Write-Host "No versions found matching $MajorMinor.* in offline source" -ForegroundColor Red
                return $null
            }
        }
        else {
            return $offlineVersions[0].Version
        }
    }

    try {
        Write-Host "Fetching available Terraform versions..." -ForegroundColor Cyan
        $response = Invoke-WebRequest -Uri "https://releases.hashicorp.com/terraform/" -UseBasicParsing

        # Extract version numbers from the HTML - look for links to version directories
        $versions = $response.Content | Select-String -Pattern 'href="\/terraform\/(\d+\.\d+\.\d+)\/"' -AllMatches | 
        ForEach-Object { $_.Matches } | 
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique |
        Where-Object { $_ -match '^\d+\.\d+\.\d+$' }  # Ensure it's a valid semantic version

        if ($MajorMinor) {
            # Filter to match major.minor pattern
            $filtered = $versions | Where-Object { $_ -like "$MajorMinor.*" } |
            Sort-Object -Descending { [version]$_ } |
            Select-Object -First 1

            if ($filtered) {
                return $filtered
            }
            else {
                Write-Host "No versions found matching $MajorMinor.*" -ForegroundColor Red
                return $null
            }
        }
        else {
            # Return the latest overall version
            $latest = $versions | Sort-Object -Descending { [version]$_ } | Select-Object -First 1
            return $latest
        }
    }
    catch {
        Write-Host "Error fetching version information: $_" -ForegroundColor Red
        Write-Host "If you're in an offline environment, enable offline mode with 'tfswitcher -Config'" -ForegroundColor Yellow
        return $null
    }
}

function Set-TFSwitcherConfig {
    param(
        [string]$TerraformPath,
        [string]$TFSwitcherPath,
        [string]$OfflineSourcePath,
        [bool]$OfflineMode,
        [switch]$PersistOfflineSource,  # Option to persist offline source to environment variable
        [switch]$PersistOfflineMode     # NEW: Option to persist offline mode to environment variable
    )

    if ($TerraformPath) {
        $script:config.TerraformPath = $TerraformPath
    }
    if ($TFSwitcherPath) {
        $script:config.TFSwitcherPath = $TFSwitcherPath
    }
    if ($OfflineSourcePath) {
        $script:config.OfflineSourcePath = $OfflineSourcePath

        # Update environment variable if requested
        if ($PersistOfflineSource) {
            try {
                [System.Environment]::SetEnvironmentVariable('TFSWITCHER_OFFLINE_SOURCE', $OfflineSourcePath, 'User')
                Write-Host "  Environment variable TFSWITCHER_OFFLINE_SOURCE updated for current user." -ForegroundColor Green
            }
            catch {
                Write-Host "  Warning: Could not update environment variable: $_" -ForegroundColor Yellow
            }
        }
    }
    if ($PSBoundParameters.ContainsKey('OfflineMode')) {
        $script:config.OfflineMode = $OfflineMode

        # Update environment variable if requested
        if ($PersistOfflineMode) {
            try {
                $envValue = if ($OfflineMode) { 'true' } else { 'false' }
                [System.Environment]::SetEnvironmentVariable('TFSWITCHER_OFFLINE_MODE', $envValue, 'User')
                $env:TFSWITCHER_OFFLINE_MODE = $envValue  # Update current session
                Write-Host "  Environment variable TFSWITCHER_OFFLINE_MODE updated for current user." -ForegroundColor Green
            }
            catch {
                Write-Host "  Warning: Could not update environment variable: $_" -ForegroundColor Yellow
            }
        }
    }

    Write-Host "Configuration updated:" -ForegroundColor Green
    Write-Host "  Terraform Path:       $($script:config.TerraformPath)" -ForegroundColor White
    Write-Host "  TFSwitcher Path:      $($script:config.TFSwitcherPath)" -ForegroundColor White
    Write-Host "  Offline Mode:         $($script:config.OfflineMode)" -ForegroundColor White
    Write-Host "  Offline Source Path:  $($script:config.OfflineSourcePath)" -ForegroundColor White
}

function Get-TFSwitcherConfig {
    # Re-check environment variable in case it was updated
    if ($env:TFSWITCHER_OFFLINE_MODE) {
        $offlineModeValue = $env:TFSWITCHER_OFFLINE_MODE.ToLower()
        if ($offlineModeValue -in @('true', '1', 'yes', 'on')) {
            $script:config.OfflineMode = $true
        }
        elseif ($offlineModeValue -in @('false', '0', 'no', 'off')) {
            $script:config.OfflineMode = $false
        }
    }

    Write-Host "`nCurrent TFSwitcher Configuration:" -ForegroundColor Cyan
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "Terraform Path:       $($script:config.TerraformPath)" -ForegroundColor White
    Write-Host "TFSwitcher Path:      $($script:config.TFSwitcherPath)" -ForegroundColor White
    Write-Host "Offline Mode:         $($script:config.OfflineMode)" -ForegroundColor White
    if ($env:TFSWITCHER_OFFLINE_MODE) {
        Write-Host "  (from environment: $($env:TFSWITCHER_OFFLINE_MODE))" -ForegroundColor Gray
    }
    Write-Host "Offline Source Path:  $($script:config.OfflineSourcePath)" -ForegroundColor White
    Write-Host ""
}

function Invoke-TFSwitcher {
    [CmdletBinding(DefaultParameterSetName = 'Help')]
    param (
        [Parameter(ParameterSetName = 'Download')]
        [switch]$Download,

        [Parameter(ParameterSetName = 'Import')]
        [switch]$Import,

        [Parameter(ParameterSetName = 'Import')]
        [string]$Path,

        [Parameter(ParameterSetName = 'Import')]
        [string]$Version,

        [Parameter(ParameterSetName = 'ListVersions')]
        [switch]$ListVersions,

        [Parameter(ParameterSetName = 'ListOffline')]  # NEW parameter set
        [switch]$ListOffline,

        [Parameter(ParameterSetName = 'SwitchVersion')]
        [switch]$SwitchVersion,

        [Parameter(ParameterSetName = 'Undo')]
        [switch]$Undo,

        [Parameter(ParameterSetName = 'Config')]
        [switch]$Config,

        [Parameter(ParameterSetName = 'Help')]
        [switch]$Help,

        [Parameter(ParameterSetName = 'Download')]
        [string]$CpuArchitecture = "amd64",

        [Parameter(ParameterSetName = 'Download')]
        [switch]$Latest
    )

    # Initialize paths if not already done
    if (-not $script:config.TerraformPath) {
        Initialize-TFSwitcherPaths
    }

    switch ($PSCmdlet.ParameterSetName) {
        'ListOffline' {
            # NEW: List available versions from offline source
            Write-Host "`nScanning offline source for Terraform versions..." -ForegroundColor Cyan

            if (-not $script:config.OfflineSourcePath) {
                Write-Host "Error: Offline source path not configured." -ForegroundColor Red
                Write-Host "Use 'tfswitcher -Config' to set the offline source path." -ForegroundColor Yellow
                return
            }

            $offlineVersions = Get-OfflineVersions

            if ($offlineVersions.Count -eq 0) {
                Write-Host "No Terraform versions found in: $($script:config.OfflineSourcePath)" -ForegroundColor Yellow
                Write-Host "`nExpected file formats:" -ForegroundColor Cyan
                Write-Host "  - terraform_X.X.X_windows_amd64.zip" -ForegroundColor Gray
                Write-Host "  - X.X.X\terraform.exe (version folders)" -ForegroundColor Gray
                Write-Host "  - terraform.exe (will auto-detect version)" -ForegroundColor Gray
            }
            else {
                Write-Host "`nFound $($offlineVersions.Count) version(s) in offline source:" -ForegroundColor Green
                Write-Host "Source: $($script:config.OfflineSourcePath)`n" -ForegroundColor Gray

                foreach ($ver in $offlineVersions) {
                    $typeColor = switch ($ver.Type) {
                        "Zip" { "Cyan" }
                        "Directory" { "Green" }
                        "Executable" { "Yellow" }
                    }
                    Write-Host "  $($ver.Version) " -ForegroundColor White -NoNewline
                    Write-Host "[$($ver.Type)]" -ForegroundColor $typeColor
                }

                Write-Host "`nUse 'tfswitcher -Download' to import versions from the offline source." -ForegroundColor Cyan
            }
            Write-Host ""
        }

        'Import' {
            # Handle local imports
            if (-not $Path) {
                $Path = Read-Host -Prompt "Enter path to Terraform executable, zip file, or directory containing terraform.exe"
            }

            $success = Import-LocalTerraform -Path $Path -Version $Version

            if ($success) {
                $autoSwitch = Read-Host -Prompt "Switch to this version now? (y/n)"
                if ($autoSwitch -eq 'y') {
                    # Get the version that was just imported
                    if (-not $Version) {
                        $exePath = if ((Get-Item $Path).PSIsContainer) {
                            Join-Path $Path "terraform.exe"
                        }
                        elseif ((Get-Item $Path).Extension -eq ".exe") {
                            $Path
                        }

                        if ($exePath -and (Test-Path $exePath)) {
                            $versionOutput = & $exePath -version | Select-Object -First 1
                            if ($versionOutput -match 'Terraform v(\d+\.\d+\.\d+)') {
                                $Version = $matches[1]
                            }
                        }
                    }

                    if ($Version) {
                        # Switch to the imported version
                        $previousPath = Join-Path $script:config.TFSwitcherPath "previous"
                        $currentExe = Join-Path $script:config.TerraformPath "terraform.exe"

                        if (Test-Path $currentExe) {
                            $originalversion = & $currentExe -version | Select-Object -First 1
                            Copy-Item -Path $currentExe -Destination (Join-Path $previousPath "terraform.exe") -Force
                            Write-Host "Backed up previous version: $originalversion" -ForegroundColor Gray
                        }

                        $newVersionExe = Join-Path $script:config.TFSwitcherPath "$Version\terraform.exe"
                        Copy-Item -Path $newVersionExe -Destination $currentExe -Force

                        $newversion = & $currentExe -version | Select-Object -First 1
                        Write-Host "Terraform is now set to: $newversion" -ForegroundColor Green
                    }
                }
            }
        }

        'Download' {
            # NEW: Check offline mode - use local directory instead
            if ($script:config.OfflineMode) {
                Write-Host "Offline mode is enabled. Scanning offline source..." -ForegroundColor Cyan

                $offlineVersions = Get-OfflineVersions

                if ($offlineVersions.Count -eq 0) {
                    Write-Host "Error: No versions found in offline source path." -ForegroundColor Red
                    Write-Host "Configure offline source path with 'tfswitcher -Config'" -ForegroundColor Yellow
                    return
                }

                $dlver = $null
                $selectedVersion = $null

                if ($Latest) {
                    # Get the latest version from offline source
                    $selectedVersion = $offlineVersions[0]
                    $dlver = $selectedVersion.Version
                    Write-Host "Latest version in offline source: $dlver" -ForegroundColor Green
                }
                else {
                    # Show available versions and prompt
                    Write-Host "`nAvailable versions in offline source:" -ForegroundColor Cyan
                    foreach ($ver in $offlineVersions) {
                        Write-Host "  $($ver.Version)" -ForegroundColor White
                    }
                    Write-Host ""

                    $versionInput = Read-Host -Prompt "Enter the Terraform version (e.g., 0.15.5, 1.2.7, or 1.5 for latest 1.5.x)"

                    # Check if it's a major.minor pattern
                    if ($versionInput -match '^\d+\.\d+$') {
                        $filtered = $offlineVersions | Where-Object { $_.Version -like "$versionInput.*" } | Select-Object -First 1
                        if ($filtered) {
                            $selectedVersion = $filtered
                            $dlver = $selectedVersion.Version
                            Write-Host "Found: $dlver" -ForegroundColor Green
                        }
                        else {
                            Write-Host "No versions found matching $versionInput.* in offline source" -ForegroundColor Red
                            return
                        }
                    }
                    else {
                        # Exact version match
                        $selectedVersion = $offlineVersions | Where-Object { $_.Version -eq $versionInput } | Select-Object -First 1
                        if ($selectedVersion) {
                            $dlver = $selectedVersion.Version
                        }
                        else {
                            Write-Host "Version $versionInput not found in offline source" -ForegroundColor Red
                            Write-Host "Use 'tfswitcher -ListOffline' to see available versions" -ForegroundColor Yellow
                            return
                        }
                    }
                }

                # Import the selected version
                Write-Host "Importing Terraform version $dlver from offline source..." -ForegroundColor Cyan
                $success = Import-LocalTerraform -Path $selectedVersion.Path -Version $dlver

                if ($success) {
                    # Automatically switch to the imported version
                    Write-Host "`nSetting Terraform to version $dlver..." -ForegroundColor Cyan

                    $previousPath = Join-Path $script:config.TFSwitcherPath "previous"
                    $currentExe = Join-Path $script:config.TerraformPath "terraform.exe"

                    if (Test-Path $currentExe) {
                        $originalversion = & $currentExe -version | Select-Object -First 1
                        Copy-Item -Path $currentExe -Destination (Join-Path $previousPath "terraform.exe") -Force
                        Write-Host "Backed up previous version: $originalversion" -ForegroundColor Gray
                    }

                    $newVersionExe = Join-Path $script:config.TFSwitcherPath "$dlver\terraform.exe"
                    Copy-Item -Path $newVersionExe -Destination $currentExe -Force

                    $newversion = & $currentExe -version | Select-Object -First 1
                    Write-Host "Terraform is now set to: $newversion" -ForegroundColor Green
                }

                return
            }

            # ONLINE MODE (existing code)
            $getstartingpath = Get-Location
            $dlver = $null

            if ($Latest) {
                # Get the absolute latest version
                $dlver = Get-LatestTerraformVersion
                if (-not $dlver) {
                    Write-Host "Could not determine latest version." -ForegroundColor Red
                    return
                }
                Write-Host "Latest Terraform version: $dlver" -ForegroundColor Green
            }
            else {
                $versionInput = Read-Host -Prompt "Enter the Terraform version (e.g., 0.15.5, 1.2.7, or 1.5 for latest 1.5.x)"

                # Check if it's a major.minor pattern (e.g., "1.5")
                if ($versionInput -match '^\d+\.\d+$') {
                    Write-Host "Searching for latest version matching $versionInput.*..." -ForegroundColor Cyan
                    $dlver = Get-LatestTerraformVersion -MajorMinor $versionInput
                    if (-not $dlver) {
                        return
                    }
                    Write-Host "Found: $dlver" -ForegroundColor Green
                    $confirm = Read-Host -Prompt "Download version $dlver? (y/n)"
                    if ($confirm -ne 'y') {
                        Write-Host "Download cancelled." -ForegroundColor Yellow
                        return
                    }
                }
                else {
                    $dlver = $versionInput
                }
            }

            # Check if version already exists
            $versionFolder = Join-Path $script:config.TFSwitcherPath $dlver
            if (Test-Path $versionFolder) {
                Write-Host "Terraform version $dlver already exists locally." -ForegroundColor Yellow
                $overwrite = Read-Host -Prompt "Do you want to re-download it? (y/n)"
                if ($overwrite -ne 'y') {
                    Write-Host "Using existing version $dlver" -ForegroundColor Cyan

                    # Still switch to this version
                    Write-Host "`nSetting Terraform to version $dlver..." -ForegroundColor Cyan

                    # Ensure previous folder exists
                    $previousPath = Join-Path $script:config.TFSwitcherPath "previous"
                    if (-not (Test-Path $previousPath)) {
                        New-Item -Path $previousPath -ItemType Directory -Force | Out-Null
                    }

                    # Backup existing version if it exists
                    $currentExe = Join-Path $script:config.TerraformPath "terraform.exe"
                    if (Test-Path $currentExe) {
                        $originalversion = & $currentExe -version | Select-Object -First 1
                        Copy-Item -Path $currentExe -Destination (Join-Path $previousPath "terraform.exe") -Force
                        Write-Host "Backed up previous version: $originalversion" -ForegroundColor Gray
                    }

                    # Copy existing version to active location
                    $newVersionExe = Join-Path $versionFolder "terraform.exe"
                    Copy-Item -Path $newVersionExe -Destination $currentExe -Force

                    # Verify the version using the full path
                    $newversion = & $currentExe -version | Select-Object -First 1
                    Write-Host "Terraform is now set to: $newversion" -ForegroundColor Green

                    # Check if Terraform directory is in PATH
                    $pathDirs = $env:Path -split ';'
                    if ($pathDirs -notcontains $script:config.TerraformPath) {
                        Write-Host "`nIMPORTANT: Add the following directory to your PATH environment variable:" -ForegroundColor Yellow
                        Write-Host "  $($script:config.TerraformPath)" -ForegroundColor White
                        Write-Host "`nOr run this command to add it for the current session:" -ForegroundColor Yellow
                        Write-Host "  `$env:Path += ';$($script:config.TerraformPath)'" -ForegroundColor Cyan
                    }

                    return
                }
            }

            Write-Host "Downloading Terraform version $dlver..." -ForegroundColor Cyan

            $zipPath = Join-Path $script:config.TFSwitcherPath "terraform_$($dlver)_windows_$($CpuArchitecture).zip"

            try {
                Invoke-WebRequest -Uri "https://releases.hashicorp.com/terraform/$dlver/terraform_$($dlver)_windows_$($CpuArchitecture).zip" -OutFile $zipPath
            }
            catch {
                Write-Host "Error downloading Terraform $dlver : $_" -ForegroundColor Red
                Set-Location $getstartingpath
                return
            }

            Set-Location $script:config.TFSwitcherPath

            $renamedZip = Join-Path $script:config.TFSwitcherPath "$($dlver).zip"
            Rename-Item $zipPath -NewName $renamedZip -Force

            # Remove existing folder if re-downloading
            if (Test-Path $versionFolder) {
                Remove-Item $versionFolder -Recurse -Force
            }

            Expand-Archive $renamedZip -Force
            Remove-Item $renamedZip -Force

            Write-Host "Successfully downloaded and extracted Terraform $dlver" -ForegroundColor Green

            # Automatically switch to the newly downloaded version
            Write-Host "`nSetting Terraform to version $dlver..." -ForegroundColor Cyan

            # Ensure previous folder exists
            $previousPath = Join-Path $script:config.TFSwitcherPath "previous"
            if (-not (Test-Path $previousPath)) {
                New-Item -Path $previousPath -ItemType Directory -Force | Out-Null
            }

            # Backup existing version if it exists
            $currentExe = Join-Path $script:config.TerraformPath "terraform.exe"
            if (Test-Path $currentExe) {
                $originalversion = & $currentExe -version | Select-Object -First 1
                Copy-Item -Path $currentExe -Destination (Join-Path $previousPath "terraform.exe") -Force
                Write-Host "Backed up previous version: $originalversion" -ForegroundColor Gray
            }

            # Copy newly downloaded version to active location
            $newVersionExe = Join-Path $script:config.TFSwitcherPath "$dlver\terraform.exe"
            Copy-Item -Path $newVersionExe -Destination $currentExe -Force

            # Verify the version using the full path (not relying on PATH)
            $newversion = & $currentExe -version | Select-Object -First 1
            Write-Host "Terraform is now set to: $newversion" -ForegroundColor Green

            # Check if Terraform directory is in PATH
            $pathDirs = $env:Path -split ';'
            if ($pathDirs -notcontains $script:config.TerraformPath) {
                Write-Host "`nIMPORTANT: Add the following directory to your PATH environment variable:" -ForegroundColor Yellow
                Write-Host "  $($script:config.TerraformPath)" -ForegroundColor White
                Write-Host "`nOr run this command to add it for the current session:" -ForegroundColor Yellow
                Write-Host "  `$env:Path += ';$($script:config.TerraformPath)'" -ForegroundColor Cyan
            }

            Set-Location $getstartingpath
        }

        'ListVersions' {
            Write-Host "`nAvailable Terraform versions:" -ForegroundColor Cyan

            $versions = Get-ChildItem -Path $script:config.TFSwitcherPath -Directory | Where-Object { $_.Name -ne "previous" }

            if ($versions) {
                $versions | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor White }
            }
            else {
                Write-Host "  No versions imported yet." -ForegroundColor Yellow
                if ($script:config.OfflineMode) {
                    Write-Host "  Use 'tfswitcher -ListOffline' to see available versions in offline source." -ForegroundColor Cyan
                    Write-Host "  Use 'tfswitcher -Download' to import from offline source." -ForegroundColor Cyan
                }
                else {
                    Write-Host "  Use 'tfswitcher -Download' or 'tfswitcher -Import' to get started." -ForegroundColor Cyan
                }
            }
            Write-Host ""
        }

        'SwitchVersion' {
            $originalversion = terraform -version | Select-Object -First 1

            if ($script:config.OfflineMode) {
                Write-Host "Note: Offline mode is enabled. Only locally imported versions are available." -ForegroundColor Yellow
            }
            else {
                Write-Host "If you require a version that is not listed, please CTRL+C and use 'tfswitcher -Download' to download the required version." -ForegroundColor Yellow
            }
            $tfver = Read-Host -Prompt "Enter the Terraform version you want to switch to"

            # Ensure previous folder exists
            $previousPath = Join-Path $script:config.TFSwitcherPath "previous"
            if (-not (Test-Path $previousPath)) {
                New-Item -Path $previousPath -ItemType Directory -Force | Out-Null
            }

            # Backup existing version
            $currentExe = Join-Path $script:config.TerraformPath "terraform.exe"
            if (Test-Path $currentExe) {
                Copy-Item -Path $currentExe -Destination (Join-Path $previousPath "terraform.exe") -Force
            }

            # Switch to requested version
            $newVersionExe = Join-Path $script:config.TFSwitcherPath "$tfver\terraform.exe"
            if (Test-Path $newVersionExe) {
                Copy-Item -Path $newVersionExe -Destination $currentExe -Force

                $newversion = terraform -version | Select-Object -First 1
                Write-Host "The version has been changed from $($originalversion) to $($newversion)." -ForegroundColor Green
            }
            else {
                Write-Host "Error: Version $tfver not found. Use 'tfswitcher -ListVersions' to see available versions." -ForegroundColor Red
            }
        }

        'Undo' {
            $previousExe = Join-Path $script:config.TFSwitcherPath "previous\terraform.exe"
            if (-not (Test-Path $previousExe)) {
                Write-Host "Error: No previous version backup found." -ForegroundColor Red
                return
            }

            # Get the existing version
            $existingversion = terraform -version | Select-Object -First 1

            # Revert to previous
            $currentExe = Join-Path $script:config.TerraformPath "terraform.exe"
            Copy-Item -Path $previousExe -Destination $currentExe -Force

            $previousversion = terraform -version | Select-Object -First 1
            Write-Host "The version has been reverted to $($previousversion) from $($existingversion)." -ForegroundColor Green
        }

        'Config' {
            Get-TFSwitcherConfig

            $changePaths = Read-Host -Prompt "Do you want to change the configuration? (y/n)"
            if ($changePaths -eq 'y') {
                $newTerraformPath = Read-Host -Prompt "Enter new Terraform path (or press Enter to keep current)"
                $newTFSwitcherPath = Read-Host -Prompt "Enter new TFSwitcher path (or press Enter to keep current)"
                $newOfflineSourcePath = Read-Host -Prompt "Enter offline source path for Terraform binaries (or press Enter to keep current)"
                $offlineModeInput = Read-Host -Prompt "Enable offline mode? (y/n/Enter to keep current)"

                if ($newTerraformPath) { $script:config.TerraformPath = $newTerraformPath }
                if ($newTFSwitcherPath) { $script:config.TFSwitcherPath = $newTFSwitcherPath }

                # Handle offline source path with optional persistence
                if ($newOfflineSourcePath) {
                    $script:config.OfflineSourcePath = $newOfflineSourcePath

                    # Ask if they want to persist to environment variable
                    $persistEnvVar = Read-Host -Prompt "Save offline source path to environment variable? (y/n)"
                    if ($persistEnvVar -eq 'y') {
                        try {
                            [System.Environment]::SetEnvironmentVariable('TFSWITCHER_OFFLINE_SOURCE', $newOfflineSourcePath, 'User')
                            Write-Host "Environment variable TFSWITCHER_OFFLINE_SOURCE updated." -ForegroundColor Green
                            Write-Host "This will be used automatically in new PowerShell sessions." -ForegroundColor Cyan
                        }
                        catch {
                            Write-Host "Warning: Could not update environment variable: $_" -ForegroundColor Yellow
                        }
                    }
                }

                # Handle offline mode with optional persistence
                if ($offlineModeInput -eq 'y') {
                    $script:config.OfflineMode = $true

                    # Ask if they want to persist to environment variable
                    $persistOfflineMode = Read-Host -Prompt "Save offline mode setting to environment variable? (y/n)"
                    if ($persistOfflineMode -eq 'y') {
                        try {
                            [System.Environment]::SetEnvironmentVariable('TFSWITCHER_OFFLINE_MODE', 'true', 'User')
                            $env:TFSWITCHER_OFFLINE_MODE = 'true'  # Update current session
                            Write-Host "Environment variable TFSWITCHER_OFFLINE_MODE updated." -ForegroundColor Green
                            Write-Host "This will be used automatically in new PowerShell sessions." -ForegroundColor Cyan
                        }
                        catch {
                            Write-Host "Warning: Could not update environment variable: $_" -ForegroundColor Yellow
                        }
                    }
                    else {
                        Write-Host "Note: This change is for the current session only." -ForegroundColor Yellow
                        if ($env:TFSWITCHER_OFFLINE_MODE) {
                            Write-Host "Environment variable is still set and will override in new sessions." -ForegroundColor Yellow
                        }
                    }
                }
                elseif ($offlineModeInput -eq 'n') {
                    $script:config.OfflineMode = $false

                    # Ask if they want to persist to environment variable
                    $persistOfflineMode = Read-Host -Prompt "Save offline mode setting to environment variable? (y/n)"
                    if ($persistOfflineMode -eq 'y') {
                        try {
                            [System.Environment]::SetEnvironmentVariable('TFSWITCHER_OFFLINE_MODE', 'false', 'User')
                            $env:TFSWITCHER_OFFLINE_MODE = 'false'  # Update current session
                            Write-Host "Environment variable TFSWITCHER_OFFLINE_MODE updated." -ForegroundColor Green
                            Write-Host "This will be used automatically in new PowerShell sessions." -ForegroundColor Cyan
                        }
                        catch {
                            Write-Host "Warning: Could not update environment variable: $_" -ForegroundColor Yellow
                        }
                    }
                    else {
                        Write-Host "Note: This change is for the current session only." -ForegroundColor Yellow
                        if ($env:TFSWITCHER_OFFLINE_MODE -and $env:TFSWITCHER_OFFLINE_MODE.ToLower() -in @('true', '1', 'yes', 'on')) {
                            Write-Host "WARNING: Environment variable TFSWITCHER_OFFLINE_MODE is set to 'true'." -ForegroundColor Red
                            Write-Host "It will re-enable offline mode in new sessions unless you persist this change." -ForegroundColor Red
                        }
                    }
                }

                Write-Host "`nConfiguration updated successfully!" -ForegroundColor Green
                Get-TFSwitcherConfig
            }
        }

        'Help' {
            Write-Host "`nTFSwitcher - Terraform Version Manager" -ForegroundColor Green
            Write-Host "======================================`n" -ForegroundColor Green
            Write-Host "Usage: tfswitcher [OPTION]`n" -ForegroundColor Cyan
            Write-Host "Options:" -ForegroundColor Yellow
            Write-Host "  -Download          Download/import a Terraform version" -ForegroundColor White
            Write-Host "                     Online: Downloads from HashiCorp" -ForegroundColor Gray
            Write-Host "                     Offline: Imports from configured offline source path" -ForegroundColor Gray
            Write-Host "                     Supports full version (1.5.7), major.minor (1.5), or -Latest flag" -ForegroundColor Gray
            Write-Host "  -Import            Import a specific local Terraform binary" -ForegroundColor White
            Write-Host "     -Path           Path to terraform.exe, zip file, or directory" -ForegroundColor Gray
            Write-Host "     -Version        (Optional) Specify version number" -ForegroundColor Gray
            Write-Host "  -ListVersions      List all locally imported Terraform versions" -ForegroundColor White
            Write-Host "  -ListOffline       List available versions in offline source path" -ForegroundColor White
            Write-Host "  -SwitchVersion     Switch to a different Terraform version" -ForegroundColor White
            Write-Host "  -Undo              Revert to the previous Terraform version" -ForegroundColor White
            Write-Host "  -Config            View or change configuration" -ForegroundColor White
            Write-Host "                     - Set offline mode" -ForegroundColor Gray
            Write-Host "                     - Configure offline source path" -ForegroundColor Gray
            Write-Host "  -Help              Display this help message" -ForegroundColor White
            Write-Host "`nExamples:" -ForegroundColor Yellow
            Write-Host "  Offline mode setup:" -ForegroundColor Cyan
            Write-Host "    tfswitcher -Config                # Enable offline mode and set source path" -ForegroundColor Gray
            Write-Host "    tfswitcher -ListOffline           # See what's available in source" -ForegroundColor Gray
            Write-Host "    tfswitcher -Download              # Import from offline source" -ForegroundColor Gray
            Write-Host "    tfswitcher -Download -Latest      # Import latest from offline source" -ForegroundColor Gray
            Write-Host "`n  Online usage:" -ForegroundColor Cyan
            Write-Host "    tfswitcher -Download              # Downloads from HashiCorp" -ForegroundColor Gray
            Write-Host "    tfswitcher -Download -Latest      # Downloads latest version" -ForegroundColor Gray
            Write-Host "`n  Manual import:" -ForegroundColor Cyan
            Write-Host "    tfswitcher -Import -Path 'C:\Downloads\terraform.exe'" -ForegroundColor Gray
            Write-Host "    tfswitcher -Import -Path 'C:\Downloads\terraform_1.5.7_windows_amd64.zip'" -ForegroundColor Gray
            Write-Host "`n  General:" -ForegroundColor Cyan
            Write-Host "    tfswitcher -ListVersions          # List imported versions" -ForegroundColor Gray
            Write-Host "    tfswitcher -SwitchVersion         # Switch to different version" -ForegroundColor Gray
            Write-Host "    tfswitcher -Undo                  # Revert to previous" -ForegroundColor Gray
            Write-Host ""

            Get-TFSwitcherConfig
        }
    }
}

# Initialize paths when module loads
Initialize-TFSwitcherPaths

# Set alias
Set-Alias -Name tfswitcher -Value Invoke-TFSwitcher -Scope Global

# Export functions
Export-ModuleMember -Function Invoke-TFSwitcher, Set-TFSwitcherConfig, Get-TFSwitcherConfig, Import-LocalTerraform, Get-OfflineVersions -Alias tfswitcher