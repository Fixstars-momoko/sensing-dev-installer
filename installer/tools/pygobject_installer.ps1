param (
    [string]$CacheDIR
)

# saving PATH before pkg-config installation
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")

$pipExists = Get-Command pip -ErrorAction SilentlyContinue

if ($pipExists){
    Write-Host "pip found; continue..."
} else {
    Write-Error "pip not found; please install it to run this script"
    exit 1
}

$defaultCacheDIR = Join-Path -Path "$env:TEMP" -ChildPath "PyGObjectCache" 

if (Test-Path $defaultCacheDIR) {
    Remove-Item -Path $defaultCacheDIR -Force -Recurse
}

# Validate if the provided CacheDIR parameter is empty
if (-not $CacheDIR) {
    Write-Output "Using default cache path: $defaultCacheDIR"
    $CacheDIR = $defaultCacheDIR
    New-Item -Path "$env:TEMP" -Name "PyGObjectCache" -ItemType "directory"
}

# Define the application ID for pkg-config-lite
$pkgConfigLiteAppId = "bloodrock.pkg-config-lite"

$pkgConfigURL = "https://sourceforge.net/projects/pkgconfiglite/files/0.28-1/pkg-config-lite-0.28-1_bin-win32.zip/download"

# Check if pkg-config-lite is already installed using winget
try {
    $installedPackage = winget show --id $pkgConfigLiteAppId -e --accept-source-agreements
    if ($installedPackage) {
        Write-Output "Uninstalling existing $pkgConfigLiteAppId..."
        winget uninstall --id $pkgConfigLiteAppId --accept-source-agreements
    }
} catch {
    Write-Error "Failed to check/uninstall existing pkg-config-lite: $_"
    exit 1
}

# Install pkg-config-lite using winget
Write-Output "Installing pkgConfig..."
$PSVersionTable
if ($PSVersionTable.PSVersion.Major -ge 7) {
    try {
        # Define the directory you want to remove from PATH
        Write-Output "The PowerShell version is 7 or greater."
        Invoke-WebRequest -UserAgent "Wget" -Uri  $pkgConfigURL -OutFile "$CacheDIR\pkg-config-lite-0.28-1_bin-win32.zip"  -AllowInsecureRedirect
        Expand-Archive -Path "$CacheDIR\pkg-config-lite-0.28-1_bin-win32.zip" -DestinationPath $CacheDIR
        $pkgconfigDirectory = "$CacheDIR\pkg-config-lite-0.28-1\bin"
    } catch {
        Write-Error "Failed to install pkg-config-lite: $_"
        exit 1
    }

} else {
    Write-Output "The PowerShell version lower than 7."
    try {
        # Define the directory you want to remove from PATH
        Invoke-WebRequest -UserAgent "Wget" -Uri  $pkgConfigURL -OutFile "$CacheDIR\pkg-config-lite-0.28-1_bin-win32.zip"
        Expand-Archive -Path "$CacheDIR\pkg-config-lite-0.28-1_bin-win32.zip" -DestinationPath $CacheDIR
        $pkgconfigDirectory = "$CacheDIR\pkg-config-lite-0.28-1\bin"
    } catch {
        Write-Error "Failed to install pkg-config-lite: $_"
        exit 1
    }
}


# this environment variable update affects only in this session
$env:PATH = "$env:PATH;$pkgconfigDirectory"
Write-Output "Added $pkgconfigDirectory to PATH for the current session"

# Install gobject-introspection using vcpkg
Write-Output "Installing gobject-introspection..."

try {
    Write-Output $CacheDIR
    Get-ChildItem -Force -LiteralPath $CacheDIR
    Invoke-WebRequest -Uri https://github.com/Sensing-Dev/aravis/releases/download/v0.8.31.post1/PyGObject-1.72.0-dependencies.zip  -OutFile $CacheDIR\dependency.zip
    Expand-Archive -Path $CacheDIR\dependency.zip -DestinationPath $CacheDIR\dependency
    Remove-Item -Force $CacheDIR\dependency.zip
} catch {
    Write-Error "Failed to DL/extract gobject-introspection: $_"
    exit 1
}

$PkgConfigPath = "$CacheDIR\dependency\pygobject_dependencies\lib\pkgconfig"
# Set the PKG_CONFIG_PATH environment variable for the current session
Write-Output "Setting PKG_CONFIG_PATH to "$PkgConfigPath" for the current session"
$Env:PKG_CONFIG_PATH = $PkgConfigPath

# Install pygobject from the Git repository with specific configuration settings
Write-Output "Installing pygobject"
try {
    pip install pygobject==3.48.2
} catch {
    Write-Error "Failed to install pygobject: $_"
    exit 1
}

# Delete the vcpkg directory recursively
Write-Output "Deleting cache directory: "$CacheDIR" ..."
try {
    Write-Output "Uninstalling $pkgConfigLiteAppId..."
    Remove-Item -Path "$CacheDIR" -Recurse -Force
} catch {
    Write-Error "Failed to remove vcpkg directory: $_"
    exit 1
}

# Unset the PKG_CONFIG_PATH environment variable
Write-Output "Removing PKG_CONFIG_PATH environment variable"
Remove-Item Env:\PKG_CONFIG_PATH

try{
    Write-Output "Clean up environment variable PATH..."
    [Environment]::SetEnvironmentVariable("Path", $currentPath, "User")
} catch {
    Write-Error "Successfully installed PyGObject but failed to uninstall pkg-config"
}

Write-Output "Script completed."






