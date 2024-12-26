#!/bin/bash
set -e
set -o noglob

setup_env() {
    if [ "$TITAN_CHANNEL" == "" ]; then
        echo "Must specify the value of TITAN_CHANNEL, example:  TITAN_CHANNEL=titan-l1"
        exit 1
    fi

    if [ "$TITAN_CHANNEL" != "titan-l1" ] && [ "$TITAN_CHANNEL" != "titan-l2" ] && [ "$TITAN_CHANNEL" != "titan-l3" ] && [ "$TITAN_CHANNEL" != "kvm" ]; then
        echo "TITAN_CHANNEL $TITAN_CHANNEL not exist"
        exit 1
    fi

    if [ "$TITAN_WORKING_DIR" == "" ]; then
        TITAN_WORKING_DIR=/opt/titan
    fi

    if [ ! -d "$TITAN_WORKING_DIR" ]; then
        echo "new dir $TITAN_WORKING_DIR"
        mkdir -p $TITAN_WORKING_DIR
    fi

    echo "TITAN_CHANNEL=$TITAN_CHANNEL"
    echo "TITAN_WORKING_DIR=$TITAN_WORKING_DIR"
    echo "KEY=$KEY"
}

uninstall_titan_agent() {
    if systemctl list-unit-files --type=service | grep -q "^titan-agent.service"; then
        systemctl stop titan-agent
        systemctl disable titan-agent
        rm /etc/systemd/system/titan-agent.service
        rm -rf /usr/local/titan-agent
        echo "uninstall titan-agent"
    fi
}

install_titan_agent_file() {
    ### download package
    wget https://agent.titannet.io/titan-agent-0.1.1.tar.gz

    ### decompress package
    tar -xvf titan-agent-0.1.1.tar.gz -C /usr/local/
    rm titan-agent-0.1.1.tar.gz

    ### change permission
    chmod +x /usr/local/titan-agent/titan-agent

}

create_systemd_service_file() {
echo "Install titan-agent service"
AGENT_SERVER_URL="https://agent.titannet.io/update/lua"
cat >/etc/systemd/system/titan-agent.service <<EOF
[Unit]
Description=titan-agent
Wants=network-online.target
After=network.target network-online.target

[Service]
Restart=always
RestartSec=3
ExecStart=/usr/local/titan-agent/titan-agent --working-dir $TITAN_WORKING_DIR --server-url $AGENT_SERVER_URL --channel $TITAN_CHANNEL

[Install]
WantedBy=multi-user.target
EOF
}

service_enable_and_start() {
    echo "service enable and start"
    systemctl enable titan-agent
    systemctl start titan-agent
}

{
    setup_env "$@"
    uninstall_titan_agent
    install_titan_agent_file
    create_systemd_service_file
    service_enable_and_start
}