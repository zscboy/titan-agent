#!/bin/bash

# Version: 0.0.1

# Define the URL for the NIULINK installation script
NIULINK_RUNNER_URL="https://download.niulinkcloud.com/init/start-smallbox-m-v1.sh"

# Function to check if Multipass is installed
function check_multipass() {
    if command -v multipass &> /dev/null; then
        # Multipass is installed, output version info
        local multipass_version
        multipass_version=$(multipass --version)
        echo "Multipass is installed. Version info: $multipass_version"
    else
        # Multipass is not installed
        echo "Error: Multipass is not installed." >&2
        exit 1
    fi
}

# Function to create the VM
function create_vm() {
    check_multipass

    local VM_NAME="ubuntu-niulink"

    # Create the virtual machine with Multipass (Ubuntu by default)
    echo "Creating the virtual machine $VM_NAME..."
    multipass launch --name "$VM_NAME" --cpus 2 --memory 2G --disk 64G

    # Check if the VM creation was successful
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create VM $VM_NAME." >&2
        exit 1
    fi

    # Fetch the installation script
    echo "Fetching the installation script..."
    multipass exec "$VM_NAME" -- wget -q "$NIULINK_RUNNER_URL" -O /tmp/start-smallbox-m-v1.sh

    # Set the execute permission on the downloaded script with sudo
    multipass exec "$VM_NAME" -- sudo chmod +x /tmp/start-smallbox-m-v1.sh

    echo "Running niulink inside the VM..."
    multipass exec "$VM_NAME" -- sudo bash /tmp/start-smallbox-m-v1.sh

    # Check if the script execution was successful
    if [[ $? -eq 0 ]]; then
        echo "The script has been executed successfully inside the VM."
    else
        echo "Error: Failed to execute script inside the VM." >&2
        exit 1
    fi
}

function info() {
    local VM_NAME="ubuntu-niulink"
    local BOX_ID
    BOX_ID=$(multipass exec "$VM_NAME" -- cat /etc/.niulink-id)
 
    if [[ -z "$BOX_ID" ]]; then
        echo "Error: BOX_ID is not found."  >&2
        exit 1
    fi
    
    echo "BOX_ID: $BOX_ID"
}

function reinstall() {
    local VM_NAME="ubuntu-niulink"
    
    if multipass list | grep -q "$VM_NAME"; then
        echo "Deleting existing $VM_NAME VM..."
        multipass delete "$VM_NAME"
        multipass purge
    fi
    
    echo "Creating new niulink VM..."
    create_vm
}


function restart() {
    local VM_NAME="ubuntu-niulink"
    
    echo "Restarting service..." 
    multipass restart "$VM_NAME"
}

function start() {
    local VM_NAME="ubuntu-niulink"
    echo "Starting service..."
    multipass start "$VM_NAME"
}

function stop() {
    local VM_NAME="ubuntu-niulink"
    echo "Stopping service..."
    multipass stop "$VM_NAME"
}



function delete() {
    local VM_NAME="ubuntu-niulink"
    
    echo "Deleting service..." 
    multipass delete "$VM_NAME"
    multipass purge
}

function status() {
    local VM_NAME="ubuntu-niulink"
    local vm_status
    vm_status=$(multipass list | grep "$VM_NAME" | awk '{print $2}')
    if [[ -z "$vm_status" ]]; then
        echo "STATUS: none"
    elif [[ "$vm_status" == "Running" ]]; then
        echo "STATUS: running"
    elif [[ "$vm_status" == "Stopped" ]]; then
        echo "STATUS: stopped"
    else
        echo "STATUS: unknown"
    fi
}
function main() {
    case $1 in
       install)
            create_vm
            ;;
        info)
            info
            ;;
        reinstall)
            reinstall
            ;;
        start)
            start
            ;;
        stop)
            stop
            ;;
        restart)
            restart
            ;;
        delete)
            delete
            ;;
        status)
            status
            ;;
        *)
            echo "Usage: $0 {install|reinstall|restart|delete|info}" >&2
            exit 1
            ;;
    esac
}

main "$@"