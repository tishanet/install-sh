#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect Linux distribution (Debian-based, Red Hat-based, or Amazon Linux)
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "amzn" && "$VERSION_ID" == "2023" ]]; then
            echo "amazon2023"
        elif [[ "$ID" == "amzn" ]]; then
            echo "amazon"
        elif [[ "$ID_LIKE" == *"debian"* || "$ID" == "debian" ]]; then
            echo "debian"
        elif [[ "$ID_LIKE" == *"rhel"* || "$ID" == "centos" ]]; then
            echo "redhat"
        else
            echo "unsupported"
        fi
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        if grep -qi "Amazon Linux 2" /etc/redhat-release; then
            echo "amazon"
        elif grep -qi "Amazon Linux" /etc/redhat-release; then
            echo "amazon2023"
        else
            echo "redhat"
        fi
    else
        echo "unsupported"
    fi
}

# Determine if the user is root or requires sudo
USER_TYPE="$(whoami)"
if [ "$USER_TYPE" = "root" ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Packages to install
REQUIRED_PACKAGES=(docker docker-compose curl wget)

# Detect distribution type
DISTRO=$(detect_distro)
if [ "$DISTRO" = "unsupported" ]; then
    echo "Unsupported Linux distribution. Exiting."
    exit 1
fi

# Install function for Debian-based distributions
install_debian() {
    $SUDO apt update -y
    $SUDO apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg
    if [ -f /usr/share/keyrings/docker-archive-keyring.gpg ]; then
        echo "Keyring file exists. Overwriting it."
        $SUDO rm -f /usr/share/keyrings/docker-archive-keyring.gpg
    fi
    curl -fsSL https://download.docker.com/linux/debian/gpg | $SUDO gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
    $SUDO apt update -y || {
        echo "APT update failed. Cleaning up Docker repository and attempting fallback installation."
        $SUDO rm -f /etc/apt/sources.list.d/docker.list
        curl -fsSL https://get.docker.com | sh
        return
    }
    $SUDO apt install -y docker-ce docker-ce-cli containerd.io docker-compose wget || {
        echo "Failed to install Docker packages from the repository. Attempting manual installation."
        $SUDO rm -f /etc/apt/sources.list.d/docker.list
        curl -fsSL https://get.docker.com | sh
    }
}

# Install function for Red Hat-based distributions
install_redhat() {
    $SUDO yum update -y
    $SUDO yum install -y yum-utils
    if [ -f /usr/share/keyrings/docker-archive-keyring.gpg ]; then
        echo "Keyring file exists. Overwriting it."
        $SUDO rm -f /usr/share/keyrings/docker-archive-keyring.gpg
    fi
    $SUDO yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    $SUDO yum install -y docker-ce docker-ce-cli containerd.io docker-compose wget
}

# Install function for Amazon Linux 2
install_amazon() {
    $SUDO yum update -y
    $SUDO yum install -y docker
    $SUDO systemctl start docker
    $SUDO systemctl enable docker
    if ! command_exists docker-compose; then
        echo "Installing docker-compose..."
        $SUDO curl -L "https://github.com/docker/compose/releases/download/$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d '"' -f 4)/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        $SUDO chmod +x /usr/local/bin/docker-compose
    fi
}

# Install function for Amazon Linux 2023
install_amazon2023() {
    $SUDO dnf update -y
    $SUDO dnf install -y docker
    $SUDO systemctl start docker
    $SUDO systemctl enable docker
    if ! command_exists docker-compose; then
        echo "Installing docker-compose..."
        $SUDO curl -L "https://github.com/docker/compose/releases/download/$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d '"' -f 4)/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        $SUDO chmod +x /usr/local/bin/docker-compose
    fi
}

# Check for and install missing packages
install_missing_packages() {
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! command_exists "$pkg"; then
            echo "$pkg is not installed. Installing..."
            if [ "$DISTRO" = "debian" ]; then
                install_debian
            elif [ "$DISTRO" = "redhat" ]; then
                install_redhat
            elif [ "$DISTRO" = "amazon" ]; then
                install_amazon
            elif [ "$DISTRO" = "amazon2023" ]; then
                install_amazon2023
            fi
        else
            echo "$pkg is already installed."
        fi
    done
}

# Start Docker service
start_docker_service() {
    if command_exists docker; then
        $SUDO systemctl start docker || echo "Docker service not found. Skipping start."
        $SUDO systemctl enable docker || echo "Docker service not found. Skipping enable."
    else
        echo "Docker not installed. Cannot start service."
    fi
}

# Verify installations
verify_installations() {
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if command_exists "$pkg"; then
            echo "$pkg version: $($pkg --version | head -n 1)"
        else
            echo "$pkg installation failed."
        fi
    done
}

# Main script logic
install_missing_packages
start_docker_service
verify_installations
