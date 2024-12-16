<#  
.SYNOPSIS
This script installs opencv-python with GStreamer support enabled.

.DESCRIPTION
The script sets up the environment and installs the `opencv-python` package 
with GStreamer functionality enabled. It is designed to work with a Python 
environment that supports custom builds of OpenCV.

.PARAMETER version
Specifies the version of OpenCV. Default is 4.10

This script performs the following:
1. Checks if Python and pip are installed.
2. Installs necessary dependencies for building OpenCV with GStreamer.
3. Installs the `opencv-contrib-python` package from a compatible source 
   that includes GStreamer support.
#>


[cmdletbinding()]
param(
  [Parameter(Mandatory=$false)][string]$version
)

$ProjectName = "sensing-dev"
$GstreamerVersion="v1.22.5.8"
$GstreamerURL="https://github.com/Sensing-Dev/gst-plugins/releases/download/$GstreamerVersion/gstreamer-$GstreamerVersion-win64.zip"

$NumpyMinimumRequirement="2.1.1"

function Invoke-Script {
    param(
          # exit code
          [Parameter(Mandatory = $false)][int32] $ProcessExit = 0
    )

    begin {
        # Clear-Host
        $script:Date = Get-Date -Format "dddd MM/dd/yyyy HH:mm K"
        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Green
        Write-Host " Start Installation opencv-python $script:Date" -ForegroundColor Green
    }
    process {
        if (-not $version){
            $version = "4.10.0.84"
        }

        ########################################################################
        # Check Python existence
        ########################################################################
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
            Write-Error "python not found; please install it before running this script"
            exit 1
        }

        ########################################################################
        # Check pip existence
        ########################################################################
        if (-not (Get-Command pip -ErrorAction SilentlyContinue)){
            Write-Error "pip not found; please install it before running this script"
            exit 1
        }

        ########################################################################
        # Check numpy version
        ########################################################################
        $CurrentNumpyVersion = python -c "import numpy; print(numpy.__version__)" 2>$null
        if ((-not $CurrentNumpyVersion) -or ($CurrentNumpyVersion -lt $NumpyMinimumRequirement)) {
            Write-Error "NumPy $NumpyMinimumRequirement or later not found; please install it before running this script"
           exit 1
        }

        ########################################################################
        # Check opencv-python
        ########################################################################
        $InstalledOpencvPython = python -m pip list | Select-String "opencv-python"
        if ($InstalledOpencvPython){
            Write-Output "opencv-python $CurrentOpenCVVersion is already installed. Unistalling..."
            pip uninstall opencv-python -y 
        }

        ########################################################################
        # Get Working Directory
        ########################################################################
        $tempWorkDir = Join-Path -Path $env:TEMP -ChildPath $ProjectName
        if (-not (Test-Path $tempWorkDir)) {
            New-Item -ItemType Directory -Path $tempWorkDir | Out-Null
        }
        Write-Verbose "Working Directory = $tempWorkDir"

        $tempExtractionPath = "$tempWorkDir\_tempExtraction"
        if (Test-Path $tempExtractionPath) {
          Remove-Item -Path $tempExtractionPath -Force -Recurse
        }
        New-Item -ItemType Directory -Path $tempExtractionPath | Out-Null

        ########################################################################
        # Get Buildtime dependencies
        ########################################################################
        Write-Output "Download build-time dependencies..."
        $ArchivePath = "$tempWorkDir/sensing-dev-gstreamer.zip"
        Invoke-WebRequest -Uri $GstreamerURL -OutFile $ArchivePath
        Expand-Archive -Path $ArchivePath -DestinationPath $tempExtractionPath

        $BuildtimeDepndency="$tempExtractionPath/sensing-dev-gstreamer"

        ########################################################################
        # Set internal environment variables
        ########################################################################
        $env:GSTREAMER_ROOT_X86 = $BuildtimeDepndency
        Write-Output "Set GSTREAMER_ROOT_X86=$env:GSTREAMER_ROOT_X86"
        $env:PATH="$BuildtimeDepndency\lib\glib-2.0\include;$BuildtimeDepndency\lib;$BuildtimeDepndency\include\glib-2.0;$BuildtimeDepndency\include\gstreamer-1.0;$env:PATH"
        Write-Output "Add PATH=$BuildtimeDepndency\lib"
        Write-Output "Add PATH=$BuildtimeDepndency\lib\glib-2.0\include"
        Write-Output "Add PATH=$BuildtimeDepndency\include\glib-2.0"
        Write-Output "Add PATH=$BuildtimeDepndency\include\gstreamer-1.0"
        $env:CMAKE_ARGS = "-DWITH_GSTREAMER=ON"
        Write-Output "Set CMAKE_ARGS=$env:CMAKE_ARGS"

        ########################################################################
        # Install opencv-python
        ########################################################################
        Write-Host "Installing opencv-python..."
        pip3 install --no-binary opencv-python opencv-python==4.10.0.84 --verbose 


    }
}

try{
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    Invoke-Script 
    [Environment]::SetEnvironmentVariable("Path", $currentPath, "User")          
}catch{
    Write-Error $_
}
