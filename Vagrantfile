
# Windows Server II - Vagrant template
#  2025-2026
# ------------------------------------
#                                      
# This is the Vagrantfile for the assignment of Windows Server II - 2025-2026. 
# The setup consists of 2 Windows Server machines (no GUI) and 1 Windows 10 client.
#
# Use `vagrant up` to bring up the environment, 
#   or `vagrant reload` to redeploy the environment after changing this file.
#
# You are allowed to modify this file as needed.
# However, you are not allowed to use any other vagrant boxes than the ones used in this file:
# - Windows Server 2025 core (no GUI): gusztavvargadr/windows-server-2025-standard-core
# - Windows 10 Enterprise 22H2: gusztavvargadr/windows-10-22h2-enterprise
# For both versions, the version is pinned to 2506.0.0 - do not change this.
# You can change the amount of vRAM and vCPU assigned to each VM if needed.
# Each VM has 2 network interfaces:
# - first adapter in (default) NAT mode, for internet access + vagrant
# - second adapter connected to a (private) Host-Only network (no IP configuration done, this needs to be done by PowerShell!)
# Use PowerShell scripts to configure the second NIC interfaces, 
#   and to install and configure the required software.
# You are allowed to add lines for automatic provisioning

Vagrant.configure("2") do |config|
  # Server 1
  config.vm.define "server1" do |server1|
    # This is the base image for the VM - do not change this!
    server1.vm.box = "gusztavvargadr/windows-server-2025-standard-core"
    server1.vm.box_version = "2506.0.0"
    # Connect the second adapter to an internal network, do not configure IP (the provided IP is just a place holder)
    server1.vm.network "private_network", ip: "192.168.25.10", auto_config: false
    # Set the host name of the VM
    server1.vm.hostname = "server1"
    # VirtualBox specific configuration
    server1.vm.provider "virtualbox" do |vb|
      # VirtualBox Display Name
      vb.name = "server1"
      # VirtualBox Group
      vb.customize ["modifyvm", :id, "--groups", "/WS2"]
      # 2GB vRAM
      vb.memory = "2048"
      # 2vCPU
      vb.cpus = "2"
    end
  end

  # Server 2
  config.vm.define "server2" do |server2|
    server2.vm.box = "gusztavvargadr/windows-server-2025-standard-core"
    server2.vm.box_version = "2506.0.0"
    server2.vm.network "private_network", ip: "192.168.25.20", auto_config: false
    server2.vm.hostname = "server2"
    server2.vm.provider "virtualbox" do |vb|
      vb.name = "server2"
      vb.customize ["modifyvm", :id, "--groups", "/WS2"]
      vb.memory = "3072"
      vb.cpus = "2"
    end
  end

  # Client
  config.vm.define "client" do |client|
    client.vm.box = "gusztavvargadr/windows-10-22h2-enterprise"
    client.vm.box_version = "2506.0.0"
    client.vm.network "private_network", ip: "192.168.25.30", auto_config: false
    client.vm.hostname = "client"
    client.vm.provider "virtualbox" do |vb|
      vb.name = "client"
      vb.customize ["modifyvm", :id, "--groups", "/WS2"]
      vb.memory = "2048"
      vb.cpus = "2"
    end
  end

  # Is Hyper-V volledig uitgeschakeld, maar krijg je nog steeds timeouts bij uitrollen van de client?
  # Verwijder dan het #-teken voor de onderstaande regel om de timeout te verhogen - indien nodig kan je de waarde nog aanpassen (default is 300 seconden)
  # config.vm.boot_timeout = 600
end
  