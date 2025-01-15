#!/bin/bash


install_frpc() {
    ### 检查frpc是否存在
    if systemctl list-units --type=service --all | grep -q "frpc.service"; then
        echo "frpc service exists"
    else
        echo "frpc service does not exist, install..."

        ### remove old file
        rm frp.tar.gz
        rm -rf /usr/local/frp

        ### install new file
        wget https://agent.titannet.io/frp/frp.tar.gz
        tar -xvf frp.tar.gz -C /usr/local
        rm frp.tar.gz
        
        UUID=$(cat /etc/machine-id)
        
        CONFIG_FILE="/usr/local/frp/frpc.toml"
        cat >$CONFIG_FILE <<EOF
serverAddr = "39.108.214.29"
serverPort = 7000

[[proxies]]
name = "$UUID"
type = "tcpmux"
multiplexer = "httpconnect"
customDomains = ["$UUID"]
localIP = "127.0.0.1"
localPort = 22
EOF


    systemctl enable /usr/local/frp/frpc.service
    systemctl start frpc

    fi
}

install_sshd() {
    ### 检查frpc是否存在
    if systemctl list-units --type=service --all | grep -q "sshd.service"; then
        echo "sshd service exists"
    else
        echo "sshd service does not exist, install..."

        apt install -y openssh-server
        systemctl enable sshd
        systemctl start sshd
    fi
}


function main() {
    install_sshd
    install_frpc
}

main