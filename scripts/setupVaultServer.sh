#!/usr/bin/env bash

export PATH=$PATH:/usr/local/bin

export DEBIAN_FRONTEND="noninteractive"
export PATH="$PATH:/usr/local/bin"

# install unzip and curl
echo "Installing dependencies ..."
apt-get -y install unzip curl


# copy vault binaries, binaries should be under ent directory, make sure to download ent vault binary to ent directory from https://releases.hashicorp.com/vault`
echo "Installing Vault enterprise version ..."
cp /vagrant/ent/vault_*.zip ./vault.zip

unzip vault.zip
chown root:root vault
chmod 0755 vault
mv vault /usr/local/bin
rm -f vault.zip

# create vault user
echo "Creating Vault service account ..."
useradd -r -d /etc/vault -s /bin/false vault

# create various directories for vault setup
echo "Creating directory structure ..."
# to copy certs
mkdir -p /etc/vault/ssl
mkdir -p /etc/transit
cp /vagrant/tls/* /etc/vault/ssl/
chown -R root:vault /etc/vault
chown -R root:vault /etc/transit
chmod -R 0750 /etc/vault

mkdir /var/{lib,log}/vault
chown vault:vault /var/{lib,log}/vault
chmod 0750 /var/{lib,log}/vault

mkdir -p /vault/raft
mkdir -p /vault/transit
chown -R vault:vault /vault/raft
chown -R vault:vault /vault/transit
chmod 0750 /vault/raft
chmod 0750 /vault/transit
mkdir -p /vault/plugins
chown -R vault:vault /vault/plugins
chmod 0750 /vault/plugins
cp /usr/local/bin/vault /vault/


echo "Creating Vault configuration ..."
echo 'export VAULT_ADDR="https://localhost:8200"' | tee /etc/profile.d/vault.sh

NETWORK_INTERFACE=$(ls -1 /sys/class/net | grep -v lo | sort -r | head -n 1)
IP_ADDRESS=$(ip address show $NETWORK_INTERFACE | awk '{print $2}' | egrep -o '([0-9]+\.){3}[0-9]+')
HOSTNAME=$(hostname -s)

echo $NETWORK_INTERFACE
echo $IP_ADDRESS
echo $HOSTNAME

# create vault instance running on 50520 port, for transit autounseal (needs vault 1.4.x or higher)
tee /etc/transit/transitvault.hcl << EOF
api_addr = "http://${IP_ADDRESS}:50520"
cluster_addr = "https://${IP_ADDRESS}:50521"
storage "raft" {
  path    = "/vault/transit/"
  node_id = "node_${HOSTNAME}"
}
listener "tcp" {
address = "0.0.0.0:50520"
tls_disable = true
}
ui = true

EOF

# create vault instance running on 8200 port (this will be HA cluster using raft Storage)
tee /etc/vault/vault.hcl << EOF
api_addr = "https://${IP_ADDRESS}:8200"
cluster_addr = "https://${IP_ADDRESS}:8201"
ui = true

storage "raft" {
  path    = "/vault/raft/"
  node_id = "node_${HOSTNAME}"

 retry_join {
    leader_api_addr = "https://10.10.42.200:8200"
    leader_ca_cert_file = "/vagrant/tls/ca.pem"
    leader_client_cert_file = "/vagrant/tls/vaults0.crt"
    leader_client_key_file = "/vagrant/tls/vaults0.key"
  }
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  #cluster_addr  = "${IP_ADDRESS}:8201"
  tls_cert_file      = "/etc/vault/ssl/${HOSTNAME}.crt"
  tls_key_file       = "/etc/vault/ssl/${HOSTNAME}.key"
  tls_client_ca_file = "/etc/vault/ssl/ca.pem"
  telemetry {
    unauthenticated_metrics_access = true
  }
}

# 2nd listner 
listener "tcp" {
  address       = "0.0.0.0:9200"
  #cluster_addr  = "${IP_ADDRESS}:9201"
  tls_cert_file      = "/etc/vault/ssl/${HOSTNAME}.crt"
  tls_key_file       = "/etc/vault/ssl/${HOSTNAME}.key"
  tls_client_ca_file = "/etc/vault/ssl/ca.pem"
}

seal "transit" {
  address            = "http://127.0.0.1:50520"
  disable_renewal    = "false"
  key_name           = "unseal_key"
  token = ""
  mount_path         = "transit/"
}

#log_level = "trace"
plugin_directory = "/vault/plugins"

telemetry {
  prometheus_retention_time = "60m"
  disable_hostname = true
}

EOF

chown -R root:vault /etc/vault
chmod 0640 /etc/vault/vault.hcl
chown -R root:vault /etc/transit
chmod 0640 /etc/transit/transitvault.hcl

# vault service

tee /etc/systemd/system/vault.service << EOF
[Unit]
Description="Vault secret management tool"
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault/vault.hcl

[Service]
User=vault
Group=vault
PIDFile=/var/run/vault/vault.pid
EnvironmentFile=/var/transit/vtoken.tok
ExecStart=/usr/local/bin/vault server -config=/etc/vault/vault.hcl
StandardOutput=file:/var/log/vault/vault.log
StandardError=file:/var/log/vault/vault.log
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=42
TimeoutStopSec=30
StartLimitInterval=60
StartLimitBurst=3
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

# transit vault services

tee /etc/systemd/system/transitvault.service << EOF
[Unit]
Description="Vault transit secret management tool"
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/transit/transitvault.hcl

[Service]
User=vault
Group=vault
PIDFile=/var/run/vault/transitvault.pid
ExecStart=/vault/vault server -config=/etc/transit/transitvault.hcl
StandardOutput=file:/var/log/vault/transitvault.log
StandardError=file:/var/log/vault/transitvault.log
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=42
TimeoutStopSec=30
StartLimitInterval=60
StartLimitBurst=3
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF


systemctl daemon-reload
systemctl enable transitvault
systemctl restart transitvault

# create transit key
export VAULT_ADDR=http://localhost:50520
mkdir /var/transit
chown -R vault:vault /var/transit
sleep 5

/usr/local/bin/vault operator init -n=1 -t=1 > /var/transit/transit_rec.key
sleep 5
/usr/local/bin/vault operator unseal `grep Unseal /var/transit/transit_rec.key | awk -F':' '{print $NF}'`
sleep 15
vault login `grep Token /var/transit/transit_rec.key | awk -F':' '{print $NF}'` 
vault secrets enable transit

tee /var/transit/autounseal.hcl << EOF
path "transit/encrypt/unseal_key" {
  capabilities = [ "update" ]
}
path "transit/decrypt/unseal_key" {
  capabilities = [ "update" ]
}
EOF

# install license 
# vault write sys/license "text=<PUT YOUR LICENSE HERE>

vault policy write autounseal /var/transit/autounseal.hcl

# restore unseal key, or create a new one
vault write /transit/restore/unseal_key "backup=eyJwb2xpY3kiOnsibmFtZSI6InVuc2VhbF9rZXkiLCJrZXlzIjp7IjEiOnsia2V5IjoiMlFXRlZNY0NOQ1Zzelp6S1AyWWdCWFRTT1ZGamxHejNrSTlzQmRuV2hMYz0iLCJobWFjX2tleSI6IklnYVFqbTlCQjg0MHk5bmtBaCtEMk84eW1UQ1VPc2JScUN0ZnVFQ3NnUTQ9IiwidGltZSI6IjIwMjAtMTAtMzBUMDM6Mjc6MDIuNjUzMjczODA5WiIsImVjX3giOm51bGwsImVjX3kiOm51bGwsImVjX2QiOm51bGwsInJzYV9rZXkiOm51bGwsInB1YmxpY19rZXkiOiIiLCJjb252ZXJnZW50X3ZlcnNpb24iOjAsImNyZWF0aW9uX3RpbWUiOjE2MDQwMjg0MjJ9fSwiZGVyaXZlZCI6ZmFsc2UsImtkZiI6MCwiY29udmVyZ2VudF9lbmNyeXB0aW9uIjpmYWxzZSwiZXhwb3J0YWJsZSI6dHJ1ZSwibWluX2RlY3J5cHRpb25fdmVyc2lvbiI6MSwibWluX2VuY3J5cHRpb25fdmVyc2lvbiI6MCwibGF0ZXN0X3ZlcnNpb24iOjEsImFyY2hpdmVfdmVyc2lvbiI6MSwiYXJjaGl2ZV9taW5fdmVyc2lvbiI6MCwibWluX2F2YWlsYWJsZV92ZXJzaW9uIjowLCJkZWxldGlvbl9hbGxvd2VkIjpmYWxzZSwiY29udmVyZ2VudF92ZXJzaW9uIjowLCJ0eXBlIjowLCJiYWNrdXBfaW5mbyI6eyJ0aW1lIjoiMjAyMC0xMC0zMFQwMzoyODoxMy4yODA3MzQ3NzdaIiwidmVyc2lvbiI6MX0sInJlc3RvcmVfaW5mbyI6bnVsbCwiYWxsb3dfcGxhaW50ZXh0X2JhY2t1cCI6dHJ1ZSwidmVyc2lvbl90ZW1wbGF0ZSI6IiIsInN0b3JhZ2VfcHJlZml4IjoiIn0sImFyY2hpdmVkX2tleXMiOnsia2V5cyI6W3sia2V5IjpudWxsLCJobWFjX2tleSI6bnVsbCwidGltZSI6IjAwMDEtMDEtMDFUMDA6MDA6MDBaIiwiZWNfeCI6bnVsbCwiZWNfeSI6bnVsbCwiZWNfZCI6bnVsbCwicnNhX2tleSI6bnVsbCwicHVibGljX2tleSI6IiIsImNvbnZlcmdlbnRfdmVyc2lvbiI6MCwiY3JlYXRpb25fdGltZSI6MH0seyJrZXkiOiIyUVdGVk1jQ05DVnN6WnpLUDJZZ0JYVFNPVkZqbEd6M2tJOXNCZG5XaExjPSIsImhtYWNfa2V5IjoiSWdhUWptOUJCODQweTlua0FoK0QyTzh5bVRDVU9zYlJxQ3RmdUVDc2dRND0iLCJ0aW1lIjoiMjAyMC0xMC0zMFQwMzoyNzowMi42NTMyNzM4MDlaIiwiZWNfeCI6bnVsbCwiZWNfeSI6bnVsbCwiZWNfZCI6bnVsbCwicnNhX2tleSI6bnVsbCwicHVibGljX2tleSI6IiIsImNvbnZlcmdlbnRfdmVyc2lvbiI6MCwiY3JlYXRpb25fdGltZSI6MTYwNDAyODQyMn1dfX0K"

export VTOKEN=`vault token create -policy="autounseal"| grep -w token | awk -F' ' '{print $NF}'`
echo "VAULT_TOKEN=$VTOKEN" > /var/transit/vtoken.tok

cp /vagrant/tls/* /usr/local/share/ca-certificates
update-ca-certificates


systemctl enable vault
systemctl restart vault


HOSTNAME=`hostname`
export VAULT_ADDR=https://localhost:8200
mkdir /var/intvault
chown -R vault:vault /var/intvault
sleep 7

if [ $HOSTNAME == 'vaults0' ] || [ $HOSTNAME == 'vaults3' ]
then
  /usr/local/bin/vault operator init -recovery-shares=1 -recovery-threshold=1 > /var/intvault/rec.key
  sleep 10
  TOKEN=`grep Token /var/intvault/rec.key | awk -F':' '{print $NF}'`
  echo $TOKEN
  vault login $TOKEN
  # install license
  # vault write /sys/license "text=<enter your license here>"
fi
