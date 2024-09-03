#!/bin/bash
: '
.SYNOPSIS
Installs the Sensing SDK.

.DESCRIPTION
This script downloads and installs the Sensing SDK components. You can specify a particular version or the latest version will be installed by default.

.PARAMETER version/-v
Specifies the version of the Sensing SDK to be installed. Default is 'latest'.

.PARAMETER user
It used to be the flag to switch .zip version and .msi version of the package. Deprecated as of v24.05.05.

.PARAMETER install-opencv
If set, the script will also install OpenCV. This is not done by default.

.PARAMETER install-path
The installation path for the Sensing SDK. Default is the sensing-dev-installer directory is the /opt/sensing-dev directory

'

installerName="sensing-dev"
repositoryName="Sensing-Dev/sensing-dev-installer"
baseUrl="https://github.com/$repositoryName/releases/download/"

version=""
installPath=""
InstallOpenCV=false

# Deprecated as of v24.05.05
user=""

# debug options
verbose=false
debugScript=false
configPath=""
archiveAravis=""
archiveAravisDep=""
archiveIonKit=""
archiveGenDCSeparator=""
archiveOpenCV=""
uninstallerPath=""

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -v | --version) version="$2"; shift ;;
    --verbose) verbose=true ;;
    --user) user="$2"; shift ;;
    --installPath) installPath="$2"; shift ;;
    --install-opencv) InstallOpenCV=true ;;
    --debugScript) debugScript=true ;;
    --config-path) configPath="$2"; shift ;;
    --archiveAravis) archiveAravis="$2"; shift ;;
    --archiveAravisDep) archiveAravisDep="$2"; shift ;;
    --archiveIonKit) archiveIonKit="$2"; shift ;;
    --archiveGenDCSeparator) archiveGenDCSeparator="$2"; shift ;;
    --archiveOpenCV) archiveOpenCV="$2"; shift ;;
    --uninstallerPath) uninstallerPath="$2"; shift ;;
    *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

verbose() {
  if [[ $verbose == true ]]; then
    echo "[verbose]" $1
  fi
}

info(){
  echo "[info]   " $1
}

error(){
  echo "[error]   " $1
}

debug(){
  echo "[debug]   " $1
}

get_latest_version() {

  curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                            # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

check_sdk_version() {
    sdkversion=$1
    verbose "Check if $sdkversion exists..."

    url="https://github.com/$repositoryName/releases/tag/$sdkversion"
    verbose "URL: $url"

    if curl --output /dev/null--silent --head --fail "$url"; then
      verbose "Valid version"
    else
      error "Version $sdkversion does not exist"
      exit 1
    fi
}

install_eariler_version() {
  reference_version=240599

  if [[ ! "$1" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)(-[a-zA-Z0-9]*)?$ ]]; then
    error "Invalid version format. Expected format is vXX.YY.ZZ or xXX.YY.ZZ-<testid>"
    exit 1
  fi

  version_major="${BASH_REMATCH[1]}"
  version_minor="${BASH_REMATCH[2]}"
  version_patch="${BASH_REMATCH[3]}"

  version_int=$((${version_major#0} * 10000 + ${version_minor#0} * 100 + ${version_patch#0}))

  if [ "$version_int" -le "$reference_version" ]; then
    prev_installer_url="$baseUrl$1/setup.sh"
    prev_installer_path="$2/tmp/old_setup.sh"
    mkdir -p "$2/tmp"
    curl -L $prev_installer_url -o "$prev_installer_path"
    verbose "Execute old_setup.sh ($1) in $prev_installer_path"
    if [ -n $3 ]; then
      bash $prev_installer_path --version $1 --install-opencv
    else 
      bash $prev_installer_path --version $1
    fi

    info "Install successfully."
    exit 0
  fi

}

verbose "version: $version"
verbose "user: $user"
verbose "installPath: $installPath"
verbose "verbose: $verbose"
verbose "InstallOpenCV: $InstallOpenCV"
verbose "debugScript: $debugScript"
verbose "configPath: $configPath"
# verbose "archiveAravis: $archiveAravis"
# verbose "archiveAravisDep: $archiveAravisDep"
# verbose "archiveIonKit: $archiveIonKit" $verbose
# verbose "archiveGenDCSeparator: $archiveGenDCSeparator"
# verbose "archiveOpenCV: $archiveOpenCV"

################################################################################
# Check Admin
################################################################################
set -eo pipefail
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

################################################################################
# Install Dependencies
################################################################################
if [[ $debugScript == true ]]; then
  debug "Skip install dependencies... (debugScript)"
else
  echo "**********"
  echo "Install Dependencies"
  echo "**********"
  apt-get -y upgrade && apt-get update && apt-get install -y \
    curl gzip git python3-pip glib2.0 libxml2-dev \
    libgirepository1.0-dev libnotify-dev \
    libunwind-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libgtk-3-dev \
    gtk-doc-tools \
    gcc libcairo2-dev pkg-config python3-dev gir1.2-gtk-4.0 \
    jq
  echo "**********"
fi

/bin/pip3 install -U pip
/bin/pip3 install pycairo

################################################################################
# Set default installPath if not provide
################################################################################
if [ -z "$installPath" ]; then
  installPath=/opt/sensing-dev
fi
verbose "installPath = $installPath"

################################################################################
# Create install directory
################################################################################
mkdir -p $installPath
if [ -d $installPath ]; then
  info "Uninstall old sensing-dev"
  rm -r -f $installPath/*
fi

################################################################################
# Get Version & config of components
################################################################################
configFileName="config_Linux.json"
if [ -n "$configPath" ]; then
  verbose "Found local $configFileName = $configPath"
  config_content=$(cat $configPath)
  version_from_config=$(echo $(echo $config_content | jq -r '.sensing_dev') | jq -r '.version')

  if [ -n "$version" ]; then
    verbose "User set verion = $version"
    if [ $version_from_config !=  $version ]; then
      error "Set vertion ($version) and config version ($version_from_config) have a conflict."
      exit 1
    fi
  else
    version=$version_from_config
  fi

elif [ -z "$version" ]; then
  # suggested installation (w/o version setting)
  verbose "Getting the latest version..."
  version=`get_latest_version $repositoryName`
else
  # suggested installation (w version setting)
  check_sdk_version $version 
fi

info "Sensing-Dev $version will be installed."
install_eariler_version $version $installPath $InstallOpenCV

if [ -z "$configPath" ]; then
  info "Download SDK Component config file..."
  configURL="$baseUrl$version/$configFileName"
  configPath="$installPath/tmp/$configFileName"
  mkdir -p "$installPath/tmp"
  curl -L $configURL -o "$configPath"
  config_content=$(cat $configPath)
fi

################################################################################
# Dlownload each component to $tempWorkDir & extract to $tempExtractionPath
################################################################################
keys=('aravis' 'ion_kit' 'gendc_separator')
for key in "${keys[@]}"
do
  comp_info=$(echo $config_content | jq -r ".$key")
  comp_name=$(echo $comp_info | jq -r '.name')
  comp_version=$(echo $comp_info | jq -r '.version')
  comp_url=$(echo $comp_info | jq -r '.pkg_url')

  echo
  echo "**********"
  echo "Install $comp_name=$comp_version"
  echo "**********"
  curl -L $comp_url | tar zx -C $installPath --strip-components 1
done

if [ -n "$InstallOpenCV" ]; then
  key='opencv'
  comp_info=$(echo $config_content | jq -r ".$key")
  comp_name=$(echo $comp_info | jq -r '.name')
  comp_version=$(echo $comp_info | jq -r '.version')
  comp_url=$(echo $comp_info | jq -r '.pkg_url')
  echo
  echo "**********"
  echo "Install $comp_name=$comp_version"
  echo "**********"
  mkdir -p "$installPath/tmp"
  curl -L https://ion-kit.s3.us-west-2.amazonaws.com/dependencies/OpenCV-4.5.2-x86_64-gcc75.sh -o "$installPath/tmp/OpenCV.sh"
  sh "$installPath/tmp/OpenCV.sh" --skip-license --prefix=$installPath
fi

################################################################################
# Create udev rule file under rules.d
################################################################################
info "Creating udev rule file..."
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/80-aravis.rules << EOS
SUBSYSTEM=="usb", ATTRS{idVendor}=="054c", MODE:="0666", TAG+="uaccess", TAG+="udev-acl"
EOS



################################################################################
# Generate version_info.json
################################################################################
info "Generating version_info.json..."
comp_info=$(echo $config_content | jq -r ".sensing_dev")
comp_name=$(echo $comp_info | jq -r '.name')
comp_version=$(echo $comp_info | jq -r '.version')
version_info_content=$(jq -n --arg $comp_name $comp_version '$ARGS.named')

compVersionInfo=$(jq -n '')
keys=('aravis' 'ion_kit' 'gendc_separator')
for key in "${keys[@]}"
do
  comp_info=$(echo $config_content | jq -r ".$key")
  comp_name=$(echo $comp_info | jq -r '.name')
  comp_version=$(echo $comp_info | jq -r '.version')
  compVersionInfo=$(echo $compVersionInfo | jq --arg $comp_name $comp_version '. += $ARGS.named')
done

if [ -n "$InstallOpenCV" ]; then
  key='opencv'
  comp_info=$(echo $config_content | jq -r ".$key")
  comp_name=$(echo $comp_info | jq -r '.name')
  comp_version=$(echo $comp_info | jq -r '.version')
  compVersionInfo=$(echo $compVersionInfo | jq --arg $comp_name $comp_version '. += $ARGS.named')
fi

version_info_content=$(echo "$version_info_content" | jq --argjson comp "$compVersionInfo" '.["SDK components"] = $comp')

echo $version_info_content | jq '.' --indent 4 > "$installPath/version_info.json"

echo "Successfully Finished."
exit 0