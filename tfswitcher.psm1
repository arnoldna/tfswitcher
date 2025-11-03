# Auto-detect or use configurable paths
$script:config = @{
    TerraformPath  = $null
    TFSwitcherPath = $null
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
    
    # Ensure previous folder exists
    $previousPath = Join-Path $script:config.TFSwitcherPath "previous"
    if (-not (Test-Path $previousPath)) {
        New-Item -Path $previousPath -ItemType Directory -Force | Out-Null
    }
}

function Get-LatestTerraformVersion {
    param(
        [string]$MajorMinor
    )
    
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
        return $null
    }
}

function Set-TFSwitcherConfig {
    param(
        [string]$TerraformPath,
        [string]$TFSwitcherPath
    )
    
    if ($TerraformPath) {
        $script:config.TerraformPath = $TerraformPath
    }
    if ($TFSwitcherPath) {
        $script:config.TFSwitcherPath = $TFSwitcherPath
    }
    
    Write-Host "Configuration updated:" -ForegroundColor Green
    Write-Host "  Terraform Path: $($script:config.TerraformPath)" -ForegroundColor White
    Write-Host "  TFSwitcher Path: $($script:config.TFSwitcherPath)" -ForegroundColor White
}

function Get-TFSwitcherConfig {
    Write-Host "`nCurrent TFSwitcher Configuration:" -ForegroundColor Cyan
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "Terraform Path:  $($script:config.TerraformPath)" -ForegroundColor White
    Write-Host "TFSwitcher Path: $($script:config.TFSwitcherPath)" -ForegroundColor White
    Write-Host ""
}

function Invoke-TFSwitcher {
    [CmdletBinding(DefaultParameterSetName = 'Help')]
    param (
        [Parameter(ParameterSetName = 'Download')]
        [switch]$Download,

        [Parameter(ParameterSetName = 'ListVersions')]
        [switch]$ListVersions,

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
        'Download' {
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
                Write-Host "  No versions downloaded yet. Use 'tfswitcher -Download' to get started." -ForegroundColor Yellow
            }
            Write-Host ""
        }

        'SwitchVersion' {
            $originalversion = terraform -version | Select-Object -First 1

            Write-Host "If you require a version that is not listed, please CTRL+C and use 'tfswitcher -Download' to download the required version." -ForegroundColor Yellow
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

            $changePaths = Read-Host -Prompt "Do you want to change the paths? (y/n)"
            if ($changePaths -eq 'y') {
                $newTerraformPath = Read-Host -Prompt "Enter new Terraform path (or press Enter to keep current)"
                $newTFSwitcherPath = Read-Host -Prompt "Enter new TFSwitcher path (or press Enter to keep current)"

                if ($newTerraformPath) { $script:config.TerraformPath = $newTerraformPath }
                if ($newTFSwitcherPath) { $script:config.TFSwitcherPath = $newTFSwitcherPath }

                Write-Host "`nConfiguration updated successfully!" -ForegroundColor Green
                Get-TFSwitcherConfig
            }
        }

        'Help' {
            Write-Host "`nTFSwitcher - Terraform Version Manager" -ForegroundColor Green
            Write-Host "======================================`n" -ForegroundColor Green
            Write-Host "Usage: tfswitcher [OPTION]`n" -ForegroundColor Cyan
            Write-Host "Options:" -ForegroundColor Yellow
            Write-Host "  -Download          Download a Terraform version" -ForegroundColor White
            Write-Host "                     Supports full version (1.5.7), major.minor (1.5), or -Latest flag" -ForegroundColor Gray
            Write-Host "  -ListVersions      List all downloaded Terraform versions" -ForegroundColor White
            Write-Host "  -SwitchVersion     Switch to a different Terraform version" -ForegroundColor White
            Write-Host "  -Undo              Revert to the previous Terraform version" -ForegroundColor White
            Write-Host "  -Config            View or change configuration paths" -ForegroundColor White
            Write-Host "  -Help              Display this help message" -ForegroundColor White
            Write-Host "`nExamples:" -ForegroundColor Yellow
            Write-Host "  tfswitcher -Download              # Prompts for version" -ForegroundColor Gray
            Write-Host "  tfswitcher -Download -Latest      # Downloads latest version" -ForegroundColor Gray
            Write-Host "  # At prompt, enter '1.5' to get latest 1.5.x patch version" -ForegroundColor Gray
            Write-Host "  tfswitcher -ListVersions" -ForegroundColor Gray
            Write-Host "  tfswitcher -SwitchVersion" -ForegroundColor Gray
            Write-Host "  tfswitcher -Undo" -ForegroundColor Gray
            Write-Host "  tfswitcher -Config" -ForegroundColor Gray
            Write-Host ""

            Get-TFSwitcherConfig
        }
    }
}

# Initialize paths when module loads
Initialize-TFSwitcherPaths

# Set alias
Set-Alias -Name tfswitcher -Value Invoke-TFSwitcher -Scope Global