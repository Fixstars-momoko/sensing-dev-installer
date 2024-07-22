<#
.SYNOPSIS
Installs the Sensing SDK.

.DESCRIPTION
This script downloads and installs the Sensing SDK components. You can specify a particular version or the latest version will be installed by default.

.PARAMETER version
Specifies the version of the Sensing SDK to be installed. Default is 'latest'.

.PARAMETER user
It used to be the flag to switch .zip version and .msi version of the package. Deprecated as of v24.05.05.

.PARAMETER installPath
The installation path for the Sensing SDK. Default is the sensing-dev-installer directory in the user's LOCALAPPDATA.

.PARAMETER InstallOpenCV
If set, the script will also install OpenCV. This is not done by default.

.EXAMPLE
PS C:\> .\installer.ps1 -version 'v24.05.06'

This example demonstrates how to run the script with custom version

.EXAMPLE
PS C:\> .\installer.ps1 -InstallOpenCV

This example demonstrates how to run the script with the default settings and includes the installation of OpenCV.

.NOTES
Ensure that you have the necessary permissions to install software and write to the specified directories.

.LINK
https://sensing-dev.github.io/doc/startup-guide/windows/index.html

#>

[cmdletbinding()]
param(
  [Parameter(Mandatory=$false)]
  [string]$version,

  [Parameter(Mandatory=$false)]
  [string]$user,

  [Parameter(Mandatory=$false)]
  [string]$installPath,

  [Parameter(Mandatory=$false)]
  [switch]$InstallOpenCV = $false,

  # for debug purporse
  [Parameter(Mandatory=$false)]
  [switch]$debugScript = $false,

  [Parameter(Mandatory=$false)]
  [string]$configPath,

  [Parameter(Mandatory=$false)]
  [string]$archiveAravis,

  [Parameter(Mandatory=$false)]
  [string]$archiveAravisDep,

  [Parameter(Mandatory=$false)]
  [string]$archiveIonKit,

  [Parameter(Mandatory=$false)]
  [string]$archiveGenDCSeparator,

  [Parameter(Mandatory=$false)]
  [string]$archiveOpenCV,

  [Parameter(Mandatory=$false)]
  [string]$uninstallerPath
)

$installerName = "sensing-dev"
$repositoryName = "Sensing-Dev/sensing-dev-installer"
$baseUrl = "https://github.com/$repositoryName/releases/download/"

function Get-LatestVersion {
  param (
  )

  $RepoApiUrl = "https://api.github.com/repos/$repositoryName/releases/latest"

  try {
    $response = Invoke-RestMethod -Uri $RepoApiUrl -Headers @{Accept = "application/vnd.github.v3+json" }
    $latestVersion = $response.tag_name

    if ($latestVersion) {
      return $latestVersion
    }
    else {
      Write-Error "Latest version not found."
      exit 1
    }
  }
  catch {
    Write-Error "Error fetching the latest version: $_"
    exit 1
  }
}



function CheckSDKVersion(){
  param(
    [string]$sdkversion
  )

  try {
    # Write-Host "https://github.com/$repositoryName/releases/$sdkversion"
    $response = Invoke-WebRequest -Uri "https://github.com/$repositoryName/releases/tag/$sdkversion" -ErrorAction Stop 
    
    if ($response.StatusCode -ne 200){
      Write-Error "Version $sdkversion does not exist"
      exit 1
    }

  } catch {
    Write-Error "Version $sdkversion does not exist"
    exit 1
  }
}



function InstallEarlierVersion(){
  param(
    [string]$sdkversion,
    [bool]$withOpenCV,
    [string]$referenceVersion = "v24.05.99"
  )

  $versionToCheck = $sdkversion.TrimStart('v')
  $referenceVersion = $referenceVersion.TrimStart('v')

  $versionParts = $versionToCheck.Split('.') | ForEach-Object { [int]$_ }
  $referenceParts = $referenceVersion.Split('.') | ForEach-Object { [int]$_ }

  for ($i = 0; $i -lt $versionParts.Length; $i++) {
      if ($versionParts[$i] -lt $referenceParts[$i]) {
        try {
          $prevInstallerURL = "${baseUrl}${version}/installer.ps1"
          $prevInstallerPath = "$tempWorkDir/old_installer.ps1"
          Invoke-WebRequest -Uri $prevInstallerURL -OutFile $prevInstallerPath
          if ($withOpenCV){
            & $prevInstallerPath -version:$sdkversion -InstallOpenCV -user:$Env:UserName
          }else{
            & $prevInstallerPath -version:$sdkversion -user:$Env:UserName
          }
          
          return $true
        } catch {
          Write-Error "Failed to download $sdkversion"
          exit 1
        }

      } elseif ($versionParts[$i] -gt $referenceParts[$i]) {
        return $false
      }
  }



}



function CheckComponentHash(){
  param(
    [string]$compName,
    [string]$archivePath,
    [string]$expectedHash
  )
  if (Test-Path "$archivePath") {
    try {

        $fileStream = [System.IO.File]::OpenRead($archivePath)
        $hashAlgorithm = [System.Security.Cryptography.HashAlgorithm]::Create("SHA256")
        $computedHashBytes = $hashAlgorithm.ComputeHash($fileStream)
        $fileStream.Close()
        
        $computedHash = [BitConverter]::ToString($computedHashBytes) -replace "-", ""
        if ($computedHash -eq $expectedHash) {
            Write-Output "The component $compName has been downloaded successfully and the hash matches."
        } else {
            throw "The hash of the downloaded $compName does not match the expected hash."
            exit 1
        }
    } catch {
        throw "Failed to compute or compare the hash of the downloaded $compName."
        exit 1
    }
  } else {
    throw "The component $compName was not downloaded."
    exit 1
  }
}



# copy all <component>/bin to <tempInstallPath> bin, <component>/lib to <tempInstallPath> lib... 
function MergeComponents(){
  param(
    [string]$CompDirName,
    [string]$tempInstallPath
  )
  # copy directories such as bin, lib, include...
  Get-ChildItem $CompDirName -Directory |
  Foreach-Object {
    $dstDir = Join-Path -Path $tempInstallPath -ChildPath $_
    $srcDir = $_.FullName
    if (-not (Test-Path $dstDir)) {
      # create dst bubm lib, include...
      New-Item -ItemType Directory -Path "$dstDir" | Out-Null
    }
    try{
      Get-ChildItem $srcDir -Recurse| 
      Foreach-Object {
        Move-Item -Force -Path (Join-Path $srcDir $_) -Destination (Join-Path $dstDir $_)
      }
    } catch {
      throw "Failed to copy the content of $_"
      exit 1
    }
  }
  # copy other files such as VERSION
  Get-ChildItem $CompDirName -File |
  Foreach-Object{
    if (-not (Test-Path $tempInstallPath)) {
      New-Item -ItemType Directory -Path $tempInstallPath | Out-Null
    }
    try{
      Move-Item -Force -Path (Join-Path $CompDirName $_) -Destination $tempInstallPath
    } catch {
      throw "Failed to copy the content of $_"
      exit 1
    }
  }

  if (-not $debugScript){
    Remove-Item -Force $CompDirName -Recurse
  }
}



function Set-EnvironmentVariables {
  param(
    [string]$SensingDevRoot,
    [bool]$InstallOpenCV
  )
  begin {
    # Clear-Host
    $script:Date = Get-Date -Format "dddd MM/dd/yyyy HH:mm K"
    Write-Host "--------------------------------------" -ForegroundColor Green
    Write-Host "Set Environment variables  $script:Date" -ForegroundColor Green
  }
  process {
    # Define the paths you want to add
    $newPath = "${SensingDevRoot}\bin"
    $newPythonPath = "${SensingDevRoot}\lib\site-packages"

    Write-Verbose "SensingDevRoot : $SensingDevRoot"

    # Get current PATH and PYTHONPATH
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $currentPythonPath = [Environment]::GetEnvironmentVariable("PYTHONPATH", "User")

    # Update PATH if the new path is not already in it
    if (-not $currentPath.Contains($newPath)) {
        $currentPath += ";$newPath" 
        [Environment]::SetEnvironmentVariable("Path", $currentPath, "User")
        Write-Output "$newPath is added to PATH"
    }
    Write-Verbose "Updated PATH: $currentPath"

    # If OpenCV is installed under sensing-dev, add <sensing-dev>/opencv/build/x64/vc*/bin to PATH
    if ($InstallOpenCV){
        $opencvBinPath = (Get-ChildItem -Path "$SensingDevRoot/opencv/build/x64/vc*/bin" -Directory)[-1]
        if ($null -eq $opencvBinPath) {
            Write-Output "No $SensingDevRoot/opencv/build/x64/vc*/bin found under Sensing-Dev; skip adding to PATH"
        } else {
            if (-not $currentPath.Contains($opencvBinPath)) {
                $currentPath += ";$opencvBinPath"
                [Environment]::SetEnvironmentVariable("Path", $currentPath, "User")
                Write-Output "$opencvBinPath is added to PATH"
            }
            Write-Verbose "Updated PATH: $currentPath"
        }
    }

    # Update PYTHONPATH if the new path is not already in it
    if (-not $currentPythonPath -or (-not $currentPythonPath.Contains($newPythonPath))) {
        if ($currentPythonPath) {
            $currentPythonPath += ";$newPythonPath"
        } else {
            $currentPythonPath = $newPythonPath
        }
        [Environment]::SetEnvironmentVariable("PYTHONPATH", $currentPythonPath, "User")
        Write-Verbose "$newPythonPath is added to PYTHONPATH"
    }
    Write-Host "Updated PYTHONPATH: $currentPythonPath"

    # Update SENSING_DEV_ROOT if the new path is not already in it
    [Environment]::SetEnvironmentVariable("SENSING_DEV_ROOT", $SensingDevRoot, "User")
    Write-Host "Updated SENSING_DEV_ROOT: $SensingDevRoot"

    $gstLibPath = "$SensingDevRoot\lib\girepository-1.0"
    [Environment]::SetEnvironmentVariable("GST_PLUGIN_PATH", $gstLibPath, "User")
    Write-Host "Updated GST_PLUGIN_PATH: $gstLibPath"
  }
}



function Generate-VersionInfo {
  param(
    [string]$SensingDevRoot,
    [bool]$InstallOpenCV,
    $compInfo
  )
  begin {
    # Clear-Host
    $script:Date = Get-Date -Format "dddd MM/dd/yyyy HH:mm K"
    Write-Host "--------------------------------------" -ForegroundColor Green
    Write-Host " version_info.json is generated under $SensingDevRoot  $script:Date" -ForegroundColor Green
  }
  process {
    $compVersionInfo = @{}
    $keys = @("aravis", "aravis_dep", "ion_kit", "gendc_separator")
    foreach ($key in $keys) {

      $compVersionInfo.Add($compInfo.$key.name, $compInfo.$key.version)
    }

    if ($InstallOpenCV){
      $compVersionInfo.Add($compInfo.opencv.name, $compInfo.opencv.version)
    }

    $jsonContent = @{
      'Sensing-Dev' = $compInfo.sensing_dev.version
    }
    $jsonContent.Add("SDK components", $compVersionInfo)

    $jsonfile = Join-Path -Path $SensingDevRoot -ChildPath 'version_info.json'
    $jsonContent | ConvertTo-Json -Depth 5 | Set-Content $jsonfile
  }
}



function Get-ConfigContent{
  param(
    [string]$configPath
  )
  if (Test-Path $configPath) {
    try {
      $content = Get-Content -Path $configPath -Raw | ConvertFrom-Json
      Write-Verbose "The config file $configPath a valid JSON."
    } catch {
      throw  "The confg file $configPath is not a valid JSON."
      exit 1
    }
  } else {
    throw  "The config file $configPath was not downloaded."
    exit 1
  }
  return $content
}


function Invoke-Script {
  param(
        # exit code
        [Parameter(Mandatory = $false)]
        [int32] $ProcessExit = 0
  )

  begin {
      # Clear-Host
      $script:Date = Get-Date -Format "dddd MM/dd/yyyy HH:mm K"
      Write-Host "--------------------------------------" -ForegroundColor Green
      Write-Host " Start Installation  $script:Date" -ForegroundColor Green
  }
  process {
    ################################################################################
    # Set default installPath if not provide
    ################################################################################
    if (-not $installPath) {
      $installPath = "$env:LOCALAPPDATA"
    }
    Write-Verbose "installPath = $installPath"

    ################################################################################
    # Get Working Directory
    ################################################################################
    $tempWorkDir = Join-Path -Path $env:TEMP -ChildPath $installerName
    if (-not (Test-Path $tempWorkDir)) {
        New-Item -ItemType Directory -Path $tempWorkDir | Out-Null
    }
    Write-Verbose "Working Directory = $tempWorkDir"

    $tempExtractionPath = "$tempWorkDir\_tempExtraction"
    if (Test-Path $tempExtractionPath) {
      Remove-Item -Path $tempExtractionPath -Force -Recurse
    }
    New-Item -ItemType Directory -Path $tempExtractionPath | Out-Null

    $tempInstallPath = "$tempWorkDir\sensing-dev"
    if (Test-Path $tempInstallPath) {
      Remove-Item -Path $tempInstallPath -Force -Recurse
    }
    New-Item -ItemType Directory -Path $tempInstallPath | Out-Null

    ################################################################################
    # Get Version & config of components
    ################################################################################
    # mainly for debug purpose (using config_Windows.json to specify versions)
    $configFileName = "config_Windows.json"
    if ($configPath){
      Write-Verbose "Found local $configFileName = $configPath"
      $content = Get-ConfigContent -configPath $configPath
      $version_from_config = $content.sensing_dev.version

      if ($version){
        Write-Host "Set vertion ($version) and config version ($version_from_config) have a conflict."
        if (-not ($version_from_config -eq $version)){
          Write-Error "Set vertion ($version) and config version ($version_from_config) have a conflict."
          exit 1
        }
      } else{
        $version = $version_from_config
      }
    }

    # suggested installation (w/ or w/o version setting)
    if (-not $version) {
      $version = Get-LatestVersion
    }else{
      CheckSDKVersion -sdkversion $version
    }
    
    Write-Host "Sensing-Dev $version will be installed." -ForegroundColor Green
    $installed = InstallEarlierVersion -sdkversion $version -withOpenCV $InstallOpenCV
    if ( $installed ){
      # Exit here if earlier version is installed.
      Write-Host "Install successfully."
      exit 0
    }

    if (-not $configPath){
      try{
        $configURL = "${baseUrl}${version}/$configFileName"
        $configPath = "$tempWorkDir/$configFileName"
        Invoke-WebRequest -Uri $configURL -OutFile $configPath
        $content = Get-ConfigContent -configPath $configPath
      } catch {
        Write-Error "Failed to obtain $configFileName of $version"
        exit 1
      }

    } 
    
    ################################################################################
    # Get Uninstaller
    ################################################################################
    $uninstallerFileName = "uninstaller.ps1"
    if (-not $uninstallerPath) {
      $uninstallerURL = "${baseUrl}${version}/$uninstallerFileName"
      $uninstallerPath = "$tempWorkDir/$uninstallerFileName"
      Invoke-WebRequest -Uri $uninstallerURL -OutFile $uninstallerPath
    } else {
      Write-Verbose "Found local $uninstallerFileName = $uninstallerPath"
      Copy-Item -Path $uninstallerPath -Destination (Join-Path $tempWorkDir $uninstallerFileName)
      $uninstallerPath = "$tempWorkDir/$uninstallerFileName"
    }

    ################################################################################
    # Dlownload each component to $tempWorkDir & extract to $tempExtractionPath
    ################################################################################ 
    $keys = @("aravis", "aravis_dep", "ion_kit", "gendc_separator")
    $archives = @($archiveAravis, $archiveAravisDep, $archiveIonKit, $archiveGenDCSeparator)

    # foreach ($key in $keys) {
    for($i = 0; $i -lt $keys.count; $i++){
      $key = $keys[$i]
      $archiveName = $archives[$i]

      if ($content.PSObject.Properties.Name -contains $key) {

        $compVersion = $content.$key.version
        $compName = $content.$key.name
        $compHash = $content.$key.pkg_sha
        $compoURL = $content.$key.pkg_url

        Write-Host "$compName $compVersion will be installed"
        if (-not $archiveName){
          $archiveName = "$tempWorkDir/$compName.zip"
          Invoke-WebRequest -Uri $compoURL -OutFile $archiveName
        }
    
        CheckComponentHash -compName $compName -archivePath $archiveName -expectedHash $compHash
        Expand-Archive -Path $archiveName -DestinationPath $tempExtractionPath 

      } else {
        throw "Component $key does not exist in $configFileName"
        exit 1
      }

      if (-not $debugScript){
        Remove-Item -Force $archiveName
      }
    }
      


    Get-ChildItem $tempExtractionPath -Directory |
    Foreach-Object {
      $CompDirName = $_.FullName

      if ($_.Name -eq "gendc_separator"){
        # GenDC Separator is a header library.
        # Move all contents under gendc_separator to under $tempInstallPath/include/gendc_separator 
        MergeComponents -CompDirName $CompDirName -tempInstallPath "$tempInstallPath/include/gendc_separator"
      }else{
        # Move all contents under $CompDirName to under $tempInstallPath
        MergeComponents -CompDirName $CompDirName -tempInstallPath $tempInstallPath
      }  
      
    }

    ################################################################################
    # Dlownload OpenCV to $tempWorkDir & extract to $tempExtractionPath
    ################################################################################
    if ($InstallOpenCV){
      $key = "opencv"
      $compVersion = $content.$key.version
      $compName = $content.$key.name
      $compHash = $content.$key.pkg_sha
      $compoURL = $content.$key.pkg_url

      Write-Host "$compName $compVersion will be installed"
      if (-not $archiveOpenCV){
        $archiveName = "$tempWorkDir/$compName.exe"
        Invoke-WebRequest -Uri $compoURL -OutFile $archiveName
      }else{
        $archiveName = $archiveOpenCV
      }
  
      CheckComponentHash -compName $compName -archivePath $archiveName -expectedHash $compHash
      Start-Process -FilePath $archiveName -ArgumentList "-o`"$tempExtractionPath`" -y" -Wait
      if (-not $debugScript){
        Remove-Item -Force $archiveName
      }

      Move-Item -Force -Path "$tempExtractionPath/opencv" -Destination $tempInstallPath
    } 
    
    ################################################################################
    # Uninstall old Sensing-Dev Move $tempInstallPath to $installPath
    ################################################################################
    $SeinsingDevRoot = Join-Path -Path $installPath -ChildPath $installerName

    Write-Host "Uninstall old sensing-dev if any" -ForegroundColor Green
    & $uninstallerPath
    Move-Item -Force -Path $tempInstallPath -Destination $installPath
    Move-Item -Force -Path $uninstallerPath -Destination $SeinsingDevRoot
    Write-Host "--------------------------------------" -ForegroundColor Green

    ################################################################################
    # Set Environment variables
    ################################################################################
    Set-EnvironmentVariables -SensingDevRoot $SeinsingDevRoot -InstallOpenCV $InstallOpenCV

    ################################################################################
    # Generate version info json
    ################################################################################
    Generate-VersionInfo -SensingDevRoot $SeinsingDevRoot -InstallOpenCV $InstallOpenCV -compInfo $content

    Write-Host "Done Sensing-Dev installation" -ForegroundColor Green
  }
}

#--------------------------------------------------------------

Invoke-Script




