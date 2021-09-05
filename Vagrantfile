# -*- mode: ruby -*-
# vi: set ft=ruby :

### Define environment variables to pass on to provisioner

# Define Vault Primary HA server details
VAULT_HA_SERVER_IP_PREFIX = ENV['VAULT_HA_SERVER_IP_PREFIX'] || "10.10.42.20"
VAULT_HA_SERVER_IPS = ENV['VAULT_HA_SERVER_IPS'] || '"10.10.42.200", "10.10.42.201", "10.10.42.202"'

# Define Vault Secondary DR server details
VAULT_DR_SERVER_IP_PREFIX = ENV['VAULT_DR_SERVER_IP_PREFIX'] || "10.10.42.20"
VAULT_DR_SERVER_IPS = ENV['VAULT_DR_SERVER_IPS'] || '"10.10.42.202", "10.10.42.203"'

# Define Vault Secondary Performance Replica server details
#VAULT_REPLICA_SERVER_IP_PREFIX = ENV['VAULT_REPLICA_SERVER_IP_PREFIX'] || "10.10.42.20"
#VAULT_REPLICA_SERVER_IPS = ENV['VAULT_REPLICA_SERVER_IPS'] || '"10.10.42.204", "10.10.42.205"'


Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/bionic64"

  # set up the 3 node Vault Primary HA servers
  (0..2).each do |i|
    config.vm.define "vaults#{i}" do |v1|
      v1.vm.hostname = "vaults#{i}"
      
      v1.vm.network "private_network", ip: VAULT_HA_SERVER_IP_PREFIX+"#{i}"
#      v1.vm.provision "shell", 
#              path: "scripts/setupConsulServer.sh",
#              env: {'VAULT_HA_SERVER_IPS' => VAULT_HA_SERVER_IPS, 'VAULT_DC' => 'dc1'}
     
      v1.vm.provision "shell", path: "scripts/setupVaultServer.sh"
    end
  end

  # set up the 2 node Vault Secondary cluster 
  (3..4).each do |i|
    config.vm.define "vaults#{i}" do |v1|
      v1.vm.hostname = "vaults#{i}"
      
      v1.vm.network "private_network", ip: VAULT_DR_SERVER_IP_PREFIX+"#{i}"
#      v1.vm.provision "shell", 
#              path: "scripts/setupConsulServer.sh",
#              env: {'VAULT_HA_SERVER_IPS' => VAULT_DR_SERVER_IPS, 'VAULT_DC' => 'dc2'}
#
      v1.vm.provision "shell", path: "scripts/setupVaultServerSec.sh"
    end
  end

# can add another cluster for secondary setup but need more certificates etc.

end
