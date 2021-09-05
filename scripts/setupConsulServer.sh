#!/usr/bin/env bash

echo "Inside setupConsulServer.sh"

export DEBIAN_FRONTEND="noninteractive"
export PATH="$PATH:/usr/local/bin"

echo "Installing dependencies ..."
apt update
apt-get -y install unzip curl jq

echo "Installing Enterprise Version"
cp /vagrant/ent/consul-enterprise_*.zip ./consul.zip

unzip consul.zip
chown root:root consul
chmod 0755 consul
mv consul /usr/local/bin
rm -f consul.zip

echo "Creating Consul service account ..."
useradd -r -d /etc/consul -s /bin/false consul

echo "Creating Consul directory structure ..."
mkdir -p /etc/consul/{config.d,pki}
chown -R root:consul /etc/consul
chmod -R 0750 /etc/consul

mkdir /var/{lib,log}/consul
chown consul:consul /var/{lib,log}/consul
chmod 0750 /var/{lib,log}/consul

echo "Creating Consul configuration file ..."
NETWORK_INTERFACE=$(ls -1 /sys/class/net | grep -v lo | sort -r | head -n 1)
IP_ADDRESS=$(ip address show $NETWORK_INTERFACE | awk '{print $2}' | egrep -o '([0-9]+\.){3}[0-9]+')
HOSTNAME=$(hostname -s)

echo "IP Address is ${IP_ADDRESS}  Host Name is ${HOSTNAME}"

cat > /etc/consul/config.d/consul.hcl << EOF
server                  = true
datacenter              = "${VAULT_DC}"
node_name               = "${HOSTNAME}"
data_dir                = "/var/lib/consul"
log_file                = "/var/log/consul/consul.log"
log_level               = "DEBUG"
enable_syslog           = true 
acl_enforce_version_8   = false
ui                      = true
bind_addr               = "0.0.0.0"
client_addr             = "0.0.0.0"
advertise_addr          = "${IP_ADDRESS}"
bootstrap_expect        = 2 
retry_join              = [${VAULT_HA_SERVER_IPS}]
EOF

chown root:consul /etc/consul/config.d/*
chmod 0640 /etc/consul/config.d/*

# Systemd configuration
echo "Setting up Consul system service ..."
cat > /etc/systemd/system/consul.service << EOF
[Unit]
Description=Consul server agent
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/consul/config.d/consul.hcl

[Service]
User=consul
Group=consul
PIDFile=/var/run/consul/consul.pid
PermissionsStartOnly=true
ExecStartPre=-/bin/mkdir -p /var/run/consul
ExecStartPre=/bin/chown -R consul:consul /var/run/consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul/config.d -pid-file=/var/run/consul/consul.pid
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
KillSignal=SIGTERM
Restart=on-failure
RestartSec=42s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo "Starting Consul service ..."
systemctl daemon-reload
systemctl enable consul
systemctl restart consul
