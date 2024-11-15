#!/bin/bash

# Create setup script
cat > setup.sh << 'EOF'
#!/bin/bash

# Add NordVPN repository
sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)

# Update and install packages
sudo apt update
sudo apt install -y openvpn iptables samba samba-common-bin dnsmasq udev
sudo apt install -y nordvpn

# Configure network interfaces
sudo cat > /etc/network/interfaces << 'END'
auto eth0
iface eth0 inet static
    address 192.168.178.188
    netmask 255.255.255.0
    gateway 192.168.178.1

auto eth1
iface eth1 inet static
    address 100.100.100.1
    netmask 255.255.255.0
END

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Configure DHCP server
sudo cat > /etc/dnsmasq.conf << 'END'
interface=eth1
dhcp-range=100.100.100.100,100.100.100.110,255.255.255.0,24h
dhcp-option=3,100.100.100.1
dhcp-option=6,8.8.8.8,8.8.4.4
dhcp-host=*,100.100.100.100,infinite
END

# Create USB mount directory
sudo mkdir -p /media/usb
sudo chmod 775 /media/usb

# Configure Samba
sudo mkdir -p /etc/samba
sudo cat > /etc/samba/smb.conf << 'END'
[global]
   workgroup = WORKGROUP
   server string = Raspberry Pi File Server
   security = user
   hosts allow = 100.100.100.0/24
   hosts deny = 0.0.0.0/0
   
[USB_Storage]
   path = /media/usb
   browseable = yes
   read only = no
   valid users = @smbgroup
   create mask = 0775
   directory mask = 0775
END

# Create Samba user and group
sudo groupadd smbgroup 2>/dev/null || true
sudo useradd -m -G smbgroup smbuser 2>/dev/null || true
echo -e "raspberry\nraspberry" | sudo smbpasswd -a smbuser

# Configure iptables
sudo iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
sudo iptables -A FORWARD -i eth1 -o tun0 -j ACCEPT
sudo iptables -A FORWARD -i tun0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo sh -c "iptables-save > /etc/iptables.rules"

# Create VPN startup service
sudo cat > /etc/systemd/system/vpn-router.service << 'END'
[Unit]
Description=VPN Router Service
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables.rules
ExecStart=/usr/sbin/nordvpn connect
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
END

# Create USB automount rules
sudo cat > /etc/udev/rules.d/99-usb-automount.rules << 'END'
ACTION=="add", KERNEL=="sd[a-z][0-9]", TAG+="systemd", ENV{SYSTEMD_WANTS}="usb-mount@%k.service"
END

sudo cat > /etc/systemd/system/usb-mount@.service << 'END'
[Unit]
Description=Mount USB Drive on %i

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/mount /dev/%i /media/usb
ExecStop=/bin/umount /media/usb

[Install]
WantedBy=multi-user.target
END

# Enable services
sudo systemctl daemon-reload
sudo systemctl enable vpn-router
sudo systemctl enable smbd
sudo systemctl enable dnsmasq

# Wait for NordVPN service to be available
sleep 5

# Setup NordVPN (requires manual login after reboot)
nordvpn set autoconnect on
nordvpn set killswitch on
nordvpn whitelist add port 22

echo "Setup complete! Please reboot and then run 'nordvpn login' to complete NordVPN setup."
EOF

# Make script executable and run
chmod +x setup.sh
sudo ./setup.sh
