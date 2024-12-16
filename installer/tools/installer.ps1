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
  [Parameter(Mandatory=$false)][string]$version,
  [Parameter(Mandatory=$false)][string]$user,
  [Parameter(Mandatory=$false)][string]$installPath,

  [Parameter(Mandatory=$false)][switch]$InstallOpenCV = $false,
  [Parameter(Mandatory=$false)][switch]$InstallGstTools = $false,
  [Parameter(Mandatory=$false)][switch]$InstallGstPlugins = $false,

  # for debug purporse >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  [Parameter(Mandatory=$false)][switch]$debugScript = $false,
  [Parameter(Mandatory=$false)][string]$configPath,
  [Parameter(Mandatory=$false)][string]$archiveAravis,
  [Parameter(Mandatory=$false)][string]$archiveAravisDep,
  [Parameter(Mandatory=$false)][string]$archiveIonKit,
  [Parameter(Mandatory=$false)][string]$archiveGenDCSeparator,
  [Parameter(Mandatory=$false)][string]$archiveOpenCV,
  [Parameter(Mandatory=$false)][string]$archiveGstTools,
  [Parameter(Mandatory=$false)][string]$archiveGstPlugin,
  [Parameter(Mandatory=$false)][string]$uninstallerPath
  # <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
)

class ComponentProperty {
  [ValidateNotNullOrEmpty()][string]  $DisplayName
  [ValidateNotNullOrEmpty()][bool]    $Install
                            [string]  $Version
                            [string]  $SHA
                            [string]  $URL
                            [string]  $LocalArchive

  ComponentProperty() { $this.Init(@{}) }

  ComponentProperty([string]$DisplayName, [bool]$Install, [string]$Version, [string]$SHA, [string]$URL, [string] $LocalArchive) { 
    $this.Init(@{DisplayName = $DisplayName; Install = $Install; Version=$Version; SHA=$SHA; URL=$URL; LocalArchive=$LocalArchive })
  }

  [void] Init([hashtable]$Properties) {
    foreach ($Property in $Properties.Keys) {
      $this.$Property = $Properties.$Property
    }
    if ($this.LocalArchive){
      #check if the local archive is valid
      CheckComponentHash -compName $this.DisplayName -archivePath $this.LocalArchive -expectedHash $this.SHA
    }
  }
}

class SDKComponents {
  [hashtable]$Dictionary = @{}

  [void]AddEntry([string]$key, [ComponentProperty]$component) {
    $this.Dictionary[$key] = $component
  }

  [void]ShowEntry([string]$key) {
    if ($this.Dictionary.ContainsKey($key)) {
      $item = $this.Dictionary[$key]
      $source = if ($item.Install){ if ($item.LocalArchive) { "Local" } else { "Online" }} else{""}
      $versioninfo = if ($item.Install){$item.Version}else{"N/A (skipped)"}

      $this.DisplayTableRow($item.DisplayName, $versioninfo, $source)

    } else {
        Write-Host "Key '$key' not found in the dictionary."
    }
  }

  [void]ShowAllEntry() {
    Write-Host "Install components:"
    Write-Host "  ================================================"
    $this.DisplayTableRow("Component Name", "Version", "Source")
    Write-Host "  ------------------------------------------------"   
    foreach($key in $this.Dictionary.Keys){
      $this.ShowEntry($key)
    }
    Write-Host "  ================================================"
  }

  [void]DisplayTableRow([string]$1, [string]$2, [string]$3){
    Write-Host ("  {0,-20} {1,-20} {2,-20}" -f $1, $2, $3)
  }

  [void]InstallAllToTempSensingDev([string]$tempWorkDir, [string]$tempExtractionPath, [string]$tempInstallPath, [bool]$keepArchive){
    foreach($key in $this.Dictionary.Keys){
      $this.InstallComponentToTempSensingDev($key, [string]$tempWorkDir, $tempExtractionPath, $tempInstallPath, $keepArchive)
    }
  }

  [void]InstallComponentToTempSensingDev([string]$key, [string]$tempWorkDir, [string]$tempExtractionPath, [string]$tempInstallPath, [bool]$keepArchive){
    if (-not $this.Dictionary.ContainsKey($key)){
      return 
    }
    
    $item = $this.Dictionary[$key]

    if (-not $item.Install){
      return
    }

    $compVersion = $item.Version
    $compName = $item.DisplayName
    $compHash = $item.SHA
    $compoURL = $item.URL
    $compArchive = $item.LocalArchive
    $compExtension = if ($key -eq "opencv") { "exe" } else { "zip" }

    $DeleteArchive = $true

    # DL or set archive
    Write-Host " - $compName $compVersion will be installed"
    if (-not $compArchive){
      Write-Host "   DL $compName..."
      $compArchive = "$tempWorkDir/$compName.$compExtension"
      Invoke-WebRequest -Uri $compoURL -OutFile $compArchive
      CheckComponentHash -compName $compName -archivePath $compArchive -expectedHash $compHash
    } else {
      Write-Host "   Use $compArchive..."
      $DeleteArchive = $false
    }

    # install archive
    if ($key -eq "opencv"){
      Start-Process -FilePath $compArchive -ArgumentList "-o`"$tempExtractionPath`" -y" -Wait
    } else {
      Expand-Archive -Path $compArchive -DestinationPath $tempExtractionPath
      Start-Sleep -Seconds 5
    }

    if ((-not $keepArchive) -and $DeleteArchive){
      Remove-Item -Force $compArchive
    }

    if ($key -eq "aravis"){
      MergeComponents -CompDirName $tempExtractionPath/$compName -tempInstallPath $tempInstallPath
    }elseif ($key -eq "aravis_dep"){
      MergeComponents -CompDirName "$tempExtractionPath/aravis_dependencies" -tempInstallPath $tempInstallPath
    }elseif ($key -eq "ion_kit"){
      $version_without_v = $compVersion.Substring(1)
      $dir_name = "ion-kit-$version_without_v-x86-64-windows"
      MergeComponents -CompDirName $tempExtractionPath/$dir_name -tempInstallPath $tempInstallPath
    }elseif ($key -eq "gendc_separator"){
      MergeComponents -CompDirName "$tempExtractionPath/gendc" -tempInstallPath $tempInstallPath
    }elseif ($key -eq "opencv"){
      Move-Item -Force -Path "$tempExtractionPath/opencv" -Destination $tempInstallPath
    }elseif ($key -eq "gst_tool"){
      MergeComponents -CompDirName "$tempExtractionPath/sensing-dev-gst-tools" -tempInstallPath $tempInstallPath
    }elseif ($key -eq "gst_plugins"){
      MergeComponents -CompDirName "$tempExtractionPath/sensing-dev-gst-plugins" -tempInstallPath $tempInstallPath
    }
  }

  [void]GenerateVersionInfoFile([string]$SavingDirectory, [string]$sdkversion){
    $content = @{}

    foreach($key in $this.Dictionary.Keys){
      $item = $this.Dictionary[$key]
      if ($item.Install){
        $content.Add($item.DisplayName, $item.Version)
      }
    }
    $jsonContent = @{
      'Sensing-Dev' = $sdkversion
    }
    $jsonContent.Add("SDK components", $content)

    $jsonfile = Join-Path -Path $SavingDirectory -ChildPath 'version_info.json'
    $jsonContent | ConvertTo-Json -Depth 5 | Set-Content $jsonfile

    Write-Host "version_info.json is saved under $SavingDirectory"
  }
}

$SDKName = "sensing-dev"
$repositoryName = "Sensing-Dev/sensing-dev-installer"
$baseUrl = "https://github.com/$repositoryName/releases/download/"

function Get-LatestVersion {
  param ()
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



function Check-SDKVersion-Valid(){
  param(
    [string]$sdkversion
  )
  try {
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
    [string]  $sdkversion,
    [bool]    $withOpenCV,
    [string]  $referenceVersion = "v24.05.99"
  )

  try{
    $versionToCheck = $sdkversion.TrimStart('v')
    $referenceVersion = $referenceVersion.TrimStart('v')
  } catch {
    Write-Error "$sdkversion does not start with v"
    exit 1
  }

  try{
    $versionParts = $versionToCheck.Split('.') | ForEach-Object { [int]$_ }
    $referenceParts = $referenceVersion.Split('.') | ForEach-Object { [int]$_ }
  } catch {
    return $false
  }

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
          Write-Error "The hash of the downloaded $compName does not match the expected hash."
          exit 1
        }
    } catch {
      Write-Error "Failed to compute or compare the hash of the downloaded $compName."
      exit 1
    }
  } else {
    Write-Error "The component $compName was not downloaded."
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
      Get-ChildItem $srcDir -Directory| 
      Foreach-Object {
        # Recursively call MergeComponents instead of Move-Item
        MergeComponents -CompDirName (Join-Path $srcDir $_) -tempInstallPath (Join-Path $dstDir $_)
        # Move-Item -Force -Path (Join-Path $srcDir $_) -Destination (Join-Path $dstDir $_)
      }

      Get-ChildItem $srcDir -File| 
      Foreach-Object {
        # Recursively call MergeComponents instead of Move-Item
        # MergeComponents -CompDirName (Join-Path $srcDir $_) -tempInstallPath (Join-Path $dstDir $_)
        Move-Item -Force -Path (Join-Path $srcDir $_) -Destination (Join-Path $dstDir $_)
      }

    } catch {
      Write-Error "Failed to copy the content of $_. Please run the script again."
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
      Write-Error "Failed to copy the content of $_. Please run the script again."
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

    $gstLibPath = "$SensingDevRoot\lib\gstreamer-1.0"
    [Environment]::SetEnvironmentVariable("GST_PLUGIN_PATH", $gstLibPath, "User")
    Write-Host "Updated GST_PLUGIN_PATH: $gstLibPath"
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
      Write-Error "The confg file $configPath is not a valid JSON."
      exit 1
    }
  } else {
    Write-Error  "The config file $configPath was not downloaded."
    exit 1
  }
  return $content
}




function Get-FileLockStatus {
  param(
    [string]$directoryPath
  )
  $fileLocked = $false

  if (Test-Path $directoryPath) {


    Get-ChildItem $directoryPath -Directory| 
      Foreach-Object {
        $ret = Get-FileLockStatus -directoryPath (Join-Path $directoryPath $_)
        $fileLocked = $fileLocked -or $ret
        if ($fileLocked){
          return $fileLocked
        }
      }

      Get-ChildItem $directoryPath -File| 
      Foreach-Object {
        $fullTargetPath = Join-Path $directoryPath $_
        try {
          $fileStream = [System.IO.File]::Open($fullTargetPath, 'Open', 'ReadWrite', 'None')
        } catch {
          $fileLocked = $true
          if ($fileLocked){
            Write-Host "$fullTargetPath is currently used in another process."
            return $fileLocked
          }
        } finally {
          if ($null -ne $fileStream) {
              $fileStream.Close()
          }
        }
      }
      return $fileLocked
    
  } else {
    return $false
  }

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
      Write-Host "Start Installation  $script:Date" -ForegroundColor Green
  }
  process {
    ################################################################################
    # Set default installPath if not provide
    ################################################################################
    if (-not $installPath) {
      $installPath = "$env:LOCALAPPDATA"
    }
    Write-Verbose "installPath = $installPath"

    if (Get-FileLockStatus -directoryPath "$installPath\sensing-dev"){
      Write-Error "Sensing-Dev ($installPath\sensing-dev) is used in another process. Please terminate it before running this script."
      exit 1
    }

    ################################################################################
    # Get Working Directory
    ################################################################################
    $tempWorkDir = Join-Path -Path $env:TEMP -ChildPath $SDKName
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
      Write-Host "Found local $configFileName : $configPath"
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
    } elseif (-not $version) {
      # suggested installation (w/o version setting)
      $version = Get-LatestVersion
    } else {
      # suggested installation (w version setting)
      Check-SDKVersion-Valid -sdkversion $version
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
    # Component version
    ################################################################################
    $install_components = [SDKComponents]::new()

    # Default items
    $keys = @("aravis", "aravis_dep", "ion_kit", "gendc_separator")
    $archives = @($archiveAravis, $archiveAravisDep, $archiveIonKit, $archiveGenDCSeparator)
    
    for($i = 0; $i -lt $keys.count; $i++){
      $key = $keys[$i]
      $archive = $archives[$i]
      $install_components.AddEntry($key, [ComponentProperty]::new($content.$key.name, $true, $content.$key.version, $content.$key.pkg_sha, $content.$key.pkg_url, $archive))
    }

    # Optional
    $keys = @("opencv", "gst_tool", "gst_plugins")
    $if_insatall = @($InstallOpenCV, $InstallGstTools, $InstallGstPlugins)
    $archives = @($archiveOpenCV, $archiveGstTools, $archiveGstPlugin)
    
    for($i = 0; $i -lt $keys.count; $i++){
      $key = $keys[$i]
      $archive = $archives[$i]
      $install_components.AddEntry($key, [ComponentProperty]::new($content.$key.name, $if_insatall[$i], $content.$key.version, $content.$key.pkg_sha, $content.$key.pkg_url, $archive))

    }
    $install_components.ShowAllEntry()
  

    
    ################################################################################
    # Get Uninstaller
    ################################################################################
    $uninstallerFileName = "uninstaller.ps1"
    if (-not $uninstallerPath) {
      $uninstallerURL = "${baseUrl}${version}/$uninstallerFileName"
      $uninstallerPath = "$tempWorkDir/$uninstallerFileName"
      try{
        Invoke-WebRequest -Uri $uninstallerURL -OutFile $uninstallerPath
      } catch {
        Write-Verbose "version $version is not available online..."
        Write-Verbose "DL uninstaller from v24.05.06 instead."
        $uninstallerURL = "${baseUrl}v24.05.06/$uninstallerFileName"
        Invoke-WebRequest -Uri $uninstallerURL -OutFile $uninstallerPath
      }
      
    } else {
      Write-Verbose "Found local $uninstallerFileName = $uninstallerPath"
      Copy-Item -Path $uninstallerPath -Destination (Join-Path $tempWorkDir $uninstallerFileName)
      $uninstallerPath = "$tempWorkDir/$uninstallerFileName"
    }

    ################################################################################
    # Dlownload each component to $tempWorkDir & extract to $tempExtractionPath
    ################################################################################ 
    try{
      $install_components.InstallAllToTempSensingDev($tempWorkDir, $tempExtractionPath, $tempInstallPath, $debugScript)
    } catch {
      Write-Error "Failed to install Sensing-Dev"
      exit 1
    }

    ################################################################################
    # Uninstall old Sensing-Dev Move $tempInstallPath to $installPath
    ################################################################################
    $SeinsingDevRoot = Join-Path -Path $installPath -ChildPath $SDKName

    Write-Host "Uninstall old sensing-dev if any" -ForegroundColor Green
    & $uninstallerPath
    Move-Item -Force -Path $tempInstallPath -Destination $installPath
    Move-Item -Force -Path $uninstallerPath -Destination $SeinsingDevRoot

    ################################################################################
    # Clean up $tempWorkDir if not $debugScript
    ################################################################################
    if (-not $debugScript){
      Remove-Item -Recurse -Force $tempWorkDir
    }

    ################################################################################
    # Set Environment variables
    ################################################################################
    Set-EnvironmentVariables -SensingDevRoot $SeinsingDevRoot -InstallOpenCV $InstallOpenCV

    ################################################################################
    # Generate version info json
    ################################################################################
    Write-Host "--------------------------------------" -ForegroundColor Green
    $install_components.GenerateVersionInfoFile($SeinsingDevRoot, $version)

    Write-Host "Done Sensing-Dev installation" -ForegroundColor Green
  }
}

#--------------------------------------------------------------

Invoke-Script




