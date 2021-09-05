## Repo to setup vault using integrated storage with vagrant


#### Documentation


#### Prerequisites

- Working Vagrant setup
- 8 Gig + RAM workstation as the (all together) Vms use 5 vCPUS and 5+ GB RAM

- Download vault ent binary from https://releases.hashicorp.com/vault/ and store it in `ent/` directory. For example I downloaded `https://releases.hashicorp.com/vault/1.7.4+ent/vault_1.7.4+ent_linux_amd64.zip` binary.


#### quick setup

-  clone repo

```
git clone https://github.com/ArunNadda/vault_integrated_storage_setup.git
cd vault_integrated_storage_setup
```
- download vault ent binary (below steps to download 1.7.4+ent)

```
vault_integrated_storage_setup % cd ent
ent % ls
readme.md

ent % wget -q https://releases.hashicorp.com/vault/1.7.4+ent/vault_1.7.4+ent_linux_amd64.zip
% ls -l
total 164384
-rw-r--r--  1 anadda  staff       116  6 Sep 09:20 readme.md
-rw-r--r--  1 anadda  staff  74100420 27 Aug 08:56 vault_1.7.4+ent_linux_amd64.zip
```
- start vault VM nodes using vagrant, this command setup two vault clusters - a 3node cluster and a 2node cluster.

```
vagrant up

# check status 
vagrant status
```


#### Usage/Examples

1. Setup 3 node vault HA cluster

- to setup vault cluster in HA mode (3 nodes)

```
git clone https://github.com/ArunNadda/vault_integrated_storage_setup.git
cd vault_integrated_storage_setup
vagrant up vaults0 vaults1 vaults2
```
- vault cluster is setup, initialized using transit autounseal. Transit vault nodes are running locally per node, with same key imported to all separate instances. It is a simple hack to avoid creating another HA cluster for transit engine and also avoid dependency between nodes for autounseal.

```
# vault transit nodes
export VAULT_ADDR=http://127.0.0.1:50520

# vault keys and root token for transit cluster
cat /var/transit/

vault login `grep Token /var/transit/transit_rec.key | awk -F':' '{print $NF}'`

``` 
- vault HA cluster has 3 nodes `vaults0, vaults1 vaults2` and is using transit autounseal and `retry_join` (check vault config file). Node `vaults0` should  be started first. Its initialized and unsealed before other nodes can join the cluster. This cluster has tls enable (using self signed certificates)

```
# vault HA cluster nodes

cd vault_integrated_storage_setup
vagrant up vaults0 vaults1 vaults2
```

- Above command will bring up vaults0 first and then join vaults1, vaults2 to cluster. vault root token and recovery keys are on `vaults0` node, to get these keys/token

```
vagrant ssh vautls0

cat /var/intvault/rec.key
```
- Access vault from inside the node

```
export VAULT_ADDR=https://127.0.0.1:8200 (set in vagrant user env)
vault login `grep Token /var/intvault/rec.key | awk -F':' '{print $NF}'`
```
- Access vault from  laptop (outside of the vault nodes)

```
export VAULT_ADDR=https://10.10.42.200:8200
vault status
```
- check raft peers

```
vault operator raft list-peers
```
- vault config file (from inside vault node)

```
cat /etc/vault/vault.hcl
```




2. To setup 2nd vault cluster (for secondaryi (DR/PerfSec) cluster), below command will bring up, initialized `vaults3` node and then `vaults4` will join it to bring 2 node cluster.

```
vagrant up vaults3 vaults4

```



#### files included in this repo 

- directory structure

```
% ls -l
total 16
-rwxr-xr-x   1 anadda  staff  1881  5 Sep 13:06 README.md
-rwxr-xr-x@  1 anadda  staff  1913  5 Sep 10:56 Vagrantfile
drwxr-xr-x   3 anadda  staff    96  5 Sep 10:52 ent
drwxr-xr-x   4 anadda  staff   128  5 Sep 12:29 keys
drwxr-xr-x   5 anadda  staff   160  5 Sep 13:01 scripts
drwxr-xr-x  17 anadda  staff   544  5 Sep 10:21 tls

% ls -l tls
total 120
-rw-r--r--  1 anadda  staff  1054  5 Sep 10:21 CERTIFICATE.crt
-rw-r--r--  1 anadda  staff   185  5 Sep 10:21 README.md
-rw-r--r--@ 1 anadda  staff  2948  5 Sep 10:21 ca.pem
-rw-r--r--  1 anadda  staff  1485  5 Sep 10:21 vaultron-int-ca.crt
-rw-r--r--  1 anadda  staff  1485  5 Sep 10:21 vaultron-root-ca.crt
-rw-r--r--@ 1 anadda  staff  1740  5 Sep 10:21 vaults0.crt
-rw-r--r--@ 1 anadda  staff  1675  5 Sep 10:21 vaults0.key
-rw-r--r--@ 1 anadda  staff  1627  5 Sep 10:21 vaults1.crt
-rw-r--r--  1 anadda  staff  1675  5 Sep 10:21 vaults1.key
-rw-r--r--@ 1 anadda  staff  1627  5 Sep 10:21 vaults2.crt
-rw-r--r--  1 anadda  staff  1679  5 Sep 10:21 vaults2.key
-rw-r--r--@ 1 anadda  staff  1627  5 Sep 10:21 vaults3.crt
-rw-r--r--@ 1 anadda  staff  1675  5 Sep 10:21 vaults3.key
-rw-r--r--@ 1 anadda  staff  1627  5 Sep 10:21 vaults4.crt
-rw-r--r--  1 anadda  staff  1675  5 Sep 10:21 vaults4.key

% ls -l scripts
total 56
-rwxr-xr-x  1 anadda  staff  2561  5 Sep 10:21 setupConsulServer.sh
-rwxr-xr-x  1 anadda  staff  8732  5 Sep 10:54 setupVaultServer.sh
-rwxr-xr-x  1 anadda  staff  8732  5 Sep 10:55 setupVaultServerSec.sh
```

#### check vagrant status, there are 5 nodes defined in vagrant file. 

```
 % vagrant status
Current machine states:

vaults0                   not created (virtualbox)
vaults1                   not created (virtualbox)
vaults2                   not created (virtualbox)
vaults3                   not created (virtualbox)
vaults4                   not created (virtualbox)

This environment represents multiple VMs. The VMs are all listed
above with their current state. For more information about a specific
VM, run `vagrant status NAME`.
```


#### to shutdown

```
vagrant halt
```


#### to start again

```
vagrant up
```

#### to destory the setup

```
vagrant destory -f
```


