chipap_dir="/etc/chipap"
chipap_user="www-data"
version=`cat /etc/debian_version`
webroot_dir="/var/www/html"

# Outputs a RaspAP INSTALL log line
function install_log() {
    echo -e "\033[1;32mChipAP INSTALL: $*\033[m"
}

# Outputs a RaspAP INSTALL ERROR log line and exits with status code 1
function install_error() {
    echo -e "\033[1;37;41mChipAP INSTALL ERROR: $*\033[m"
    exit 1
}

### NOTE: all the below functions are overloadable for system-specific installs
### NOTE: some of the below functions MUST be overloaded due to system-specific installs

function config_installation() {
    install_log "Configure installation"
    echo -n "Install directory [${chipap_dir}]: "
    read input
    if [ ! -z "$input" ]; then
        chipap_dir="$input"
    fi

    echo -n "Complete installation with these values? [y/N]: "
    read answer
    if [[ $answer != "y" ]]; then
        echo "Installation aborted."
        exit 0
    fi
}

# Runs a system software update to make sure we're using all fresh packages
function update_system_packages() {
    # OVERLOAD THIS
    install_error "No function definition for update_system_packages"
}

# Installs additional dependencies using system package manager
function install_dependencies() {
    # OVERLOAD THIS
    install_error "No function definition for install_dependencies"
}

# Enables PHP for lighttpd and restarts service for settings to take effect
function enable_php_lighttpd() {
    install_log "Enabling PHP for lighttpd"

    sudo lighty-enable-mod fastcgi-php || install_error "Cannot enable fastcgi-php for lighttpd"
    sudo /etc/init.d/lighttpd restart || install_error "Unable to restart lighttpd"
}

# Verifies existence and permissions of RaspAP directory
function create_chipap_directories() {
    install_log "Creating ChipAP directories"
    if [ -d "$chipap_dir" ]; then
        sudo mv $chipap_dir $chipap_dir.original || install_error "Unable to move old '$chipap_dir' out of the way"
    fi
    sudo mkdir -p "$chipap_dir" || install_error "Unable to create directory '$chipap_dir'"

    sudo chown -R $chipap_user:$chipap_user "$chipap_dir" || install_error "Unable to change file ownership for '$chipap_dir'"
}

# Fetches latest files from github to webroot
function download_latest_files() {
    if [ -d "$webroot_dir" ]; then
        sudo mv $webroot_dir /tmp/old_webroot || install_error "Unable to remove old webroot directory"
    fi

    install_log "Cloning latest files from github"
    git clone https://github.com/pimpmypixel/chipap-webgui /tmp/chipap-webgui || install_error "Unable to download files from github"
    sudo mv /tmp/chipap-webgui $webroot_dir || install_error "Unable to move chipap-webgui to web root"
}

# Sets files ownership in web root directory
function change_file_ownership() {
    if [ ! -d "$webroot_dir" ]; then
        install_error "Web root directory doesn't exist"
    fi

    install_log "Changing file ownership in web root directory"
    sudo chown -R $chipap_user:$chipap_user "$webroot_dir" || install_error "Unable to change file ownership for '$webroot_dir'"
}

# Move configuration file to the correct location
function move_config_file() {
    if [ ! -d "$chipap_dir" ]; then
        install_error "'$chipap_dir' directory doesn't exist"
    fi

    install_log "Moving configuration file to '$chipap_dir'"
    sudo mv "$webroot_dir"/chipap.php "$chipap_dir" || install_error "Unable to move files to '$chipap_dir'"
    sudo chown -R $chipap_user:$chipap_user "$chipap_dir" || install_error "Unable to change file ownership for '$chipap_dir'"
}

# Set up default configuration
function default_configuration() {
    install_log "Setting up hostapd"
    if [ -f /etc/default/hostapd ]; then
        sudo mv /etc/default/hostapd /tmp/default_hostapd.old || install_error "Unable to remove old /etc/default/hostapd file"
    fi
    sudo mv $webroot_dir/config/default_hostapd /etc/default/hostapd || install_error "Unable to move hostapd defaults file"
    sudo mv $webroot_dir/config/hostapd.conf /etc/hostapd/hostapd.conf || install_error "Unable to move hostapd configuration file"
    sudo mv $webroot_dir/config/dnsmasq.conf /etc/dnsmasq.conf || install_error "Unable to move dnsmasq configuration file"
    sudo mv $webroot_dir/config/dhcpcd.conf /etc/dhcpcd.conf || install_error "Unable to move dhcpcd configuration file"
    sudo mv $webroot_dir/config/rc.local /etc/rc.local || install_error "Unable to move rc.local file"
}

# Add a single entry to the sudoers file
function sudo_add() {
  sudo bash -c "echo \"www-data ALL=(ALL) NOPASSWD:$1\" | (EDITOR=\"tee -a\" visudo)" \
        || install_error "Unable to patch /etc/sudoers"
}

# Adds www-data user to the sudoers file with restrictions on what the user can execute
function patch_system_files() {
    # patch /etc/sudoers file
    install_log "Patching system sudoers file"
    sudo_add '/sbin/ifdown wlan0'
    sudo_add '/sbin/ifup wlan0'
    sudo_add '/bin/cat /etc/wpa_supplicant/wpa_supplicant.conf'
    sudo_add '/bin/cp /tmp/wifidata /etc/wpa_supplicant/wpa_supplicant.conf'
    sudo_add '/sbin/wpa_cli scan_results'
    sudo_add '/sbin/wpa_cli scan'
    sudo_add '/sbin/wpa_cli reconfigure'
    sudo_add '/bin/cp /tmp/hostapddata /etc/hostapd/hostapd.conf'
    sudo_add '/etc/init.d/hostapd start'
    sudo_add '/etc/init.d/hostapd stop'
    sudo_add '/etc/init.d/dnsmasq start'
    sudo_add '/etc/init.d/dnsmasq stop'
    sudo_add '/bin/cp /tmp/dhcpddata /etc/dnsmasq.conf'
    sudo_add '/sbin/shutdown -h now'
    sudo_add '/sbin/reboot'
}

function install_complete() {
    install_log "Installation completed!"
    
    echo -n "The system needs to be rebooted as a final step. Reboot now? [y/N]: "
    read answer
    if [[ $answer != "y" ]]; then
        echo "Installation aborted."
        exit 0
    fi
    sudo shutdown -r now || install_error "Unable to execute shutdown"
}

function install_chipap() {
    config_installation
    update_system_packages
    install_dependencies
    enable_php_lighttpd
    create_chipap_directories
    download_latest_files
    change_file_ownership
    move_config_file
    default_configuration
    patch_system_files
    install_complete
}
