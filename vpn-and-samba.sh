#!/bin/bash

# Create setup script
cat > setup.sh << 'EOF'
#!/bin/bash

# Update and install packages
sudo apt update && sudo apt install -y openvpn nordvpn usbmount samba samba-common-bin dnsmasq

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
dhcp-range=100.100.100.100,100.100.100.110,12h
END

# Configure Samba
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

# Setup USB mount directories
sudo mkdir -p /media/usb
sudo chmod 775 /media/usb

# Create Samba user and group
sudo groupadd smbgroup
sudo useradd -m -G smbgroup smbuser
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

# Setup NordVPN (requires manual login after reboot)
nordvpn set autoconnect on
nordvpn set killswitch on

echo "Setup complete! Please reboot and then run 'nordvpn login' to complete NordVPN setup."
EOF

# Make script executable and run
chmod +x setup.sh
sudo ./setup.sh
