
 
#!/bin/bash
# Version 2.0 - March 2025
# Developer: Jaime Galvez (TheHellishPandaa)
# Description: Bash script for configuring gateway server, DHCP, SAMBA, OpenSSH, etc.
# This Script is released under GNU General public license.
# If you like my work, please support it with a start in my github´s profile

clear

# Check if exec in superuser permissions. 
if [ $EUID -ne 0 ]; then
   echo "This script must be run with superuser permissions (sudo)"
   exit 1
fi

configure_firewall() {


    echo "==============================================================================="
    echo "=========================== Firewall SETUP ===================================="
    echo "==============================================================================="

    # Asegurarse de que UFW está instalado
    if ! command -v ufw &>/dev/null; then
        echo "UFW no está instalado. Install UFW (Uncomplicated Firewall)..."
        apt update && apt install ufw -y
    fi

    # Verificar si UFW está activo
    if sudo ufw status | grep -q "inactive"; then
        echo "Activating UFW..."
        sudo ufw enable
    else
        echo "UFW is already active."
    fi

    while true; do
        echo "Select an option to configure the firewall:"
        echo "1) Allow access to a specific port"
        echo "2) Allow access to a specific port via specific IP"
        echo "3) Show firewall rules"
        echo "4) Install Firewall"
        echo "5) Activate Firewall"
        echo "6) Disable Firewall"
        echo "7) Exit"
        read -p "Choose an option: " opcion

        case $opcion in
            1)  # Permitir acceso a un puerto específico
                read -p "Input the port to allow (e.g., 80, 443, 22): " puerto
                echo "Allowing access to port $puerto..."
                sudo ufw allow "$puerto"
                echo "Port $puerto allowed."
                ;;
            2)  # Permitir acceso a un puerto específico desde una IP
                read -p "Input the port to allow (e.g., 80, 443, 22): " puerto
                read -p "Input the IP (e.g., 192.168.1.100): " ip
                echo "Allowing access to port $puerto from IP $ip..."
                sudo ufw allow from "$ip" to any port "$puerto"
                echo "Access to port $puerto from IP $ip allowed."
                ;;
            3)  # Ver reglas actuales
                echo "Showing current firewall rules..."
                sudo ufw status verbose
                ;;
            4)  # Install UFW
                echo "Installing UFW..."
                sudo apt update -y
                sudo apt install ufw -y
                ;;
            5)  # Activate firewall
                echo "Activating firewall..."
                sudo ufw enable
                ;;
            6)  # Disable Firewall
                echo "Disabling firewall..."
                sudo ufw disable
                ;;
            7)  # Salir
                echo "Exiting firewall configuration."
                break
                ;;
            *)  # Opción no válida
                echo "Invalid option."
                ;;
        esac
    done
}



install_forwarder_dns() {
    



# Ask the user which type of DNS server they want to install
echo "Select the type of DNS server to install:"
echo "1) Forwarding DNS Server"
echo "2) Caching DNS Server"
read -p "Enter the number of the desired option: " option

# Update packages and install Bind9
sudo apt update && sudo apt install -y bind9

if [ "$option" == "1" ]; then
    # Configure Bind9 as a forwarding DNS server
    sudo bash -c 'cat > /etc/bind/named.conf.options <<EOF
options {
    directory "/var/cache/bind";
    
    recursion yes;
    allow-recursion { any; };
    
    forwarders {
        8.8.8.8;  // Google DNS
        8.8.4.4;  // Google Secondary DNS
        1.1.1.1;  // Cloudflare DNS
        1.0.0.1;  // Cloudflare Secondary DNS
    };
    
    dnssec-validation auto;
    listen-on { any; };
    listen-on-v6 { any; };
};
EOF'
elif [ "$option" == "2" ]; then
    # Configure Bind9 as a caching DNS server
    sudo bash -c 'cat > /etc/bind/named.conf.options <<EOF
options {
    directory "/var/cache/bind";
    
    recursion yes;
    allow-query { any; };
    
    dnssec-validation auto;
    listen-on { any; };
    listen-on-v6 { any; };
};
EOF'
else
    echo "Invalid option. Exiting..."
    exit 1
fi

# Restart Bind9 to apply changes
sudo systemctl restart bind9
sudo systemctl enable bind9

# Check the service status
sudo systemctl status bind9 --no-pager

}

configure_network() {
    # Display available network interfaces (excluding lo)
    echo "Available network interfaces:"
    echo "--------------------------------"
    ip -o link show | awk -F': ' '!/ lo:/{print $2}' | while read -r interface; do
        mac=$(cat /sys/class/net/$interface/address)
        echo "Interface: $interface - MAC: $mac"
    done

    echo "--------------------------------"

    # Ask the user to select an interface
    read -p "Enter the network interface you want to configure: " interface

    # Ask if they want a static IP or DHCP
    echo "Do you want to configure a Static IP or use DHCP?"
    echo "1) Static IP"
    echo "2) DHCP (Automatic)"
    read -p "Select an option (1 or 2): " option

    # Initialize variables
    dns_servers=""
    gateway=""

    if [[ "$option" == "1" ]]; then
        # Static IP Configuration
        read -p "Enter the IP address (e.g., 192.168.1.100): " ip_address
        read -p "Enter the CIDR prefix (e.g., 24 for 255.255.255.0): " cidr
        read -p "Enter the gateway (or press Enter to skip): " gateway

        # Ask if the user wants to configure custom DNS servers
        read -p "Do you want to configure custom DNS servers? (y/n): " configure_dns
        if [[ "$configure_dns" =~ ^[Yy]$ ]]; then
            read -p "Enter DNS servers (comma-separated, e.g., 8.8.8.8,8.8.4.4): " dns_servers
        fi

        # Validate CIDR prefix
        if ! [[ "$cidr" =~ ^[0-9]+$ ]] || [ "$cidr" -lt 1 ] || [ "$cidr" -gt 32 ]; then
            echo "Error: CIDR prefix must be a number between 1 and 32."
            exit 1
        fi

        # Create Netplan configuration for Static IP
        sudo tee /etc/netplan/01-netcfg.yaml > /dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $interface:
      dhcp4: no
      addresses:
        - $ip_address/$cidr
EOF

        # Add gateway if provided
        if [[ -n "$gateway" ]]; then
            sudo tee -a /etc/netplan/01-netcfg.yaml > /dev/null <<EOF
      gateway4: $gateway
EOF
        fi

        # Add DNS configuration if the user provided DNS servers
        if [[ -n "$dns_servers" ]]; then
            sudo tee -a /etc/netplan/01-netcfg.yaml > /dev/null <<EOF
      nameservers:
        addresses: [$dns_servers]
EOF
        fi

    elif [[ "$option" == "2" ]]; then
        # Ask if the user wants to configure custom DNS servers
        read -p "Do you want to configure custom DNS servers? (y/n): " configure_dns
        if [[ "$configure_dns" =~ ^[Yy]$ ]]; then
            read -p "Enter DNS servers (comma-separated, e.g., 8.8.8.8,8.8.4.4): " dns_servers
        fi

        # Create Netplan configuration for DHCP
        sudo tee /etc/netplan/01-netcfg.yaml > /dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $interface:
      dhcp4: yes
EOF

        # Add DNS configuration if the user provided DNS servers
        if [[ -n "$dns_servers" ]]; then
            sudo tee -a /etc/netplan/01-netcfg.yaml > /dev/null <<EOF
      nameservers:
        addresses: [$dns_servers]
EOF
        fi

    else
        echo "Invalid option. You must choose 1 or 2."
        exit 1
    fi

    # Adjust Netplan file permissions to avoid warnings
    sudo chmod 600 /etc/netplan/01-netcfg.yaml

    # Apply Netplan configuration
    sudo netplan apply

    echo "Network configuration successfully applied. 🚀"
}

# Configure gateway server

configure_gateway_server(){


echo "------------------------------------------------"
echo "----------- MAKE GATEWAY ON UBUNTU -------------"
echo "------------------------------------------------"
echo "                                               "

#show network interfaces in the system
 echo "--------------------------------------"
    echo "Network interfaces in your system:"
    echo "--------------------------------------"
    INTERFACES=$(ip link show | awk -F': ' '{print $1,  $2}')
    echo "$INTERFACES"
    echo "======================================"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root. Exit"
  exit 1
fi

read -p "Enter the WAN Interface: " WAN_INTERFACE
read -p "Enter the LAN Interface: " LAN_INTERFACE

# Network Interface Variables

# Update system
echo "Updating the system..."
apt update && apt upgrade -y

# Install iptables if not installed
echo "Installing iptables..."
apt install -y iptables iptables-persistent

# Enable IP forwarding
echo "Enabling IP forwarding..."
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Flush existing iptables rules (optional)
echo "Flushing existing iptables rules..."
iptables -F
iptables -t nat -F

# Configure iptables for NAT
echo "Configuring NAT in iptables..."
iptables -t nat -A POSTROUTING -o $WAN_INTERFACE -j MASQUERADE
iptables -A FORWARD -i $WAN_INTERFACE -o $LAN_INTERFACE -j ACCEPT
iptables -A FORWARD -i $LAN_INTERFACE -o $WAN_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save iptables rules
echo "Saving iptables rules..."
netfilter-persistent save

# Restart iptables service
echo "Restarting the iptables service..."
systemctl restart netfilter-persistent

# Enable iptables-persistent to start on boot
echo "Enabling iptables-persistent at boot..."
systemctl enable netfilter-persistent

echo "Gateway successfully configured on $WAN_INTERFACE and $LAN_INTERFACE."
}

# Configure DHCP Server
configure_dhcp_server() {
# A tool for creating and managing a DHCP server with MAC filtering in an Ubuntu 20.04 system or later


    echo "================================="
    echo "Configuring DHCP Server..."
    echo "================================="
    echo "1) Assign an IP to a MAC"
    echo "2) Block an IP"
    echo "3) Change Network Configuration"
    echo "4) Install DHCP Server"
    echo "5) Exit"
    read -p "Choose an option: " dhcp_option
    case $dhcp_option in
        1)
            read -p "Enter the MAC address of the device: " mac
            read -p "Enter the IP to assign: " ip
            echo "host device_$mac {
    hardware ethernet $mac;
    fixed-address $ip;
}" >> /etc/dhcp/dhcpd.conf
            echo "Assigned IP $ip to MAC $mac."
            ;;
        2)
            read -p "Enter the IP to block: " ip_blocked
            echo "deny booting from $ip_blocked;" >> /etc/dhcp/dhcpd.conf
            echo "Blocked IP $ip_blocked in the DHCP server."
            ;;
        3)
            echo "Updating network configuration for the DHCP server..."
            read -p "Enter the network (e.g., 192.168.1.0): " network
            read -p "Enter the netmask (e.g., 255.255.255.0): " netmask
            read -p "Enter the range of IPs to assign (e.g., 192.168.1.100 192.168.1.200): " range
            read -p "Enter the gateway: " gateway
            echo "
subnet $network netmask $netmask {
    range $range;
    option routers $gateway;
}" >> /etc/dhcp/dhcpd.conf
            echo "Updated network settings for the DHCP server."
            ;;
        4)
            echo "======================="
            echo "Installing DHCP Server"
            echo "======================="
            
            #show interfaces
            echo ""
            echo "++++++++++++++++++++++++++++++++"
            echo "Available interfaces"
            echo "++++++++++++++++++++++++++++++++"
            INTERFACES=$(ip link show | awk -F': ' '{print $1,  $2}')
            echo "$INTERFACES"
            echo "++++++++++++++++++++++++++++++++"
            echo ""

	  # Ask the user to input the network interface name
  read -p "Enter the network interface for the DHCP server (e.g., ens19): " interface_name
  
  apt update && apt install -y isc-dhcp-server
  if [ $? -ne 0 ]; then
    echo "Error installing the DHCP server."
    exit 1
  fi

  # Configure the network interface
  echo "INTERFACESv4=\"$interface_name\"" > /etc/default/isc-dhcp-server

  # Configure the dhcpd.conf file with basic settings
  configure_dhcp

  # Restart and enable the DHCP service
  systemctl restart isc-dhcp-server
  systemctl enable isc-dhcp-server

  echo "DHCP server configured on interface $interface_name with network 10.33.206.0/24."

# Function to configure the dhcpd.conf file
configure_dhcp() {
  # Backup the configuration file
  cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak
  
  read -p "Enter the subnet (e.g., 10.33.206.0): " subnet
  read -p "Enter the subnet mask (e.g., 255.255.255.0): " subnet_mask
  read -p "Enter the starting IP range (e.g., 10.33.206.100): " range_start
  read -p "Enter the ending IP range (e.g., 10.33.206.200): " range_end
  read -p "Enter the router IP (e.g., 10.33.206.1): " router_ip
  read -p "Enter the DNS servers separated by commas (e.g., 8.8.8.8, 8.8.4.4): " dns_servers
  read -p "Enter the domain name (e.g., network.local): " domain_name

  # Write the configuration to dhcpd.conf
  cat <<EOL > /etc/dhcp/dhcpd.conf
# DHCP server configuration
subnet $subnet netmask $subnet_mask {
    range $range_start $range_end;
    option routers $router_ip;
    option subnet-mask $subnet_mask;
    option domain-name-servers $dns_servers;
    option domain-name "$domain_name";
}
EOL
}
            ;;
        5)
            echo "Exiting DHCP configuration."
            return ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
    # Restart the service after any change
    systemctl restart isc-dhcp-server
    echo "DHCP server configured and restarted."
}


configure_acl(){


# Ask the user what they want to configure
echo "What would you like to configure?"
echo "1) Block Traffic To LAN to WAN Network"
echo " ----------------------------------------"
echo "2) Configure QoS"
echo "-----------------------------------------"
read -p "Choose an option (1 or 2): " OPTION

case $OPTION in
    1)


# Display available network interfaces
echo "Available network interfaces:"
ip link show | awk -F': ' '/^[0-9]+: / {print $2}'

# Ask the user for interfaces and WAN network
echo -e "\nLAN to WAN Traffic Blocking Configuration"
read -p "Enter the WAN interface name: " WAN_IF
read -p "Enter the LAN interface name: " LAN_IF
read -p "Enter the WAN network (e.g., 192.168.1.0/24): " WAN_NET

# Check if interfaces exist
if ! ip link show "$WAN_IF" >/dev/null 2>&1; then
    echo "Error: The WAN interface '$WAN_IF' does not exist."
    exit 1
fi

if ! ip link show "$LAN_IF" >/dev/null 2>&1; then
    echo "Error: The LAN interface '$LAN_IF' does not exist."
    exit 1
fi

# Enable packet forwarding in sysctl
echo "Enabling packet forwarding..."
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Flush previous iptables rules
echo "Flushing previous rules..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Set default policies
echo "Setting default policies..."
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT  # Allow outgoing traffic from the gateway

# Allow loopback traffic
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow the gateway itself to access the internet
echo "Allowing the gateway to access the internet..."
iptables -A INPUT -i "$WAN_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT

# Block LAN -> WAN internal network traffic
echo "Configuring firewall rules..."
iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -d "$WAN_NET" -j DROP  

# Allow LAN -> Internet traffic
iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i "$WAN_IF" -o "$LAN_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT

# Enable NAT for internet access
iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE

# Save iptables rules to persist after reboot
echo "Saving iptables rules..."
iptables-save > /etc/iptables.rules

# Apply rules on startup (Debian/Ubuntu)
echo -e "#!/bin/sh\n/sbin/iptables-restore < /etc/iptables.rules" > /etc/network/if-pre-up.d/iptables
chmod +x /etc/network/if-pre-up.d/iptables

# Display configured rules
echo "Configured rules:"
iptables -L -v -n
echo "Configuration completed."

 ;;

    
    2)
        # Configure QoS on the LAN interface
        echo "Enter the LAN network interface (example: eth0):"
        read LAN_IF
        echo "Enter the bandwidth limit in Kbps (example: 1000):"
        read BANDWIDTH

        # Validate the bandwidth
        if ! [[ "$BANDWIDTH" =~ ^[0-9]+$ ]]; then
            echo "The bandwidth limit must be an integer number."
            exit 1
        fi

        tc qdisc add dev "$LAN_IF" root handle 1: htb default 10
        tc class add dev "$LAN_IF" parent 1: classid 1:1 htb rate "${BANDWIDTH}kbit"
        tc filter add dev "$LAN_IF" protocol ip parent 1:0 prio 1 handle 1 fw flowid 1:1

        # Save the rules to persist after reboot
        echo "tc qdisc add dev $LAN_IF root handle 1: htb default 10" >> /etc/qos.rules
        echo "tc class add dev $LAN_IF parent 1: classid 1:1 htb rate ${BANDWIDTH}kbit" >> /etc/qos.rules
        echo "tc filter add dev $LAN_IF protocol ip parent 1:0 prio 1 handle 1 fw flowid 1:1" >> /etc/qos.rules

        echo "QoS configured with a bandwidth limit of ${BANDWIDTH} Kbps on the interface $LAN_IF"
        ;;
    
    *)
        echo "Invalid option. Exiting."
        exit 1
        ;;
esac

}

# Change FQDN Name
configure_fqdn_name() {


    read -p "New FQDN (e.g., server.example.com): " NEW_FQDN
    NEW_HOSTNAME=$(echo $NEW_FQDN | cut -d '.' -f 1)
    echo $NEW_HOSTNAME > /etc/hostname
    echo "127.0.1.1 $NEW_FQDN $NEW_HOSTNAME" >> /etc/hosts

    hostnamectl set-hostname $NEW_HOSTNAME
    echo "================================================"
    echo "          FQDN updated to $NEW_FQDN             "
    echo "================================================"
    echo ""
    echo ""

}

# Install samba server

install_samba_server() {

echo "---------------------------------------------------"
echo "----------- Configure Samba Server ----------------"
echo "---------------------------------------------------"
echo ""
# Upgrade system and the dependencias
echo "Upgrade System..."
apt update && apt upgrade -y

# Install Samba
echo "Install Samba..."
apt install samba -y

echo "==============================================================================="
echo ""
# Ask to the user the share folder`s name
read -p "What do you want to call the shared folder? " carpeta_compartida

# Ask to the user if the shared folder will be writable or not
read -p "Do you want the folder to be writable? (y/n): " escribible

# Create the shared folder
ruta_carpeta="/srv/samba/$carpeta_compartida"
mkdir -p "$ruta_carpeta"

# Apply Permissions to the shared folder
chmod 770 "$ruta_carpeta"  #Allows the owner and group to have all permissions, but denies access to others. 
chown nobody:nogroup "$ruta_carpeta"

# Configure Samba
SMB_CONF="/etc/samba/smb.conf"
echo "Configuring Samba..."

# Apply config to the smb.conf file
{
    echo ""
    echo "[$carpeta_compartida]"
    echo "   path = $ruta_carpeta"
    echo "   available = yes"
    echo "   valid users = @sambashare"
    echo "   read only = no"
    echo "   browsable = yes"
    echo "   public = yes"
    if [[ "$escribible" == "y" || "$escribible" == "Y" ]]; then
        echo "   writable = yes"
    else
        echo "   writable = no"
    fi
} >> "$SMB_CONF"

# Esto a lo mejor se cambia
# Create a group for the samba users
groupadd sambashare

# Create a Samba user (if it does not exist)
read -p "Input the Username for Samba: " usuario
useradd -m -G sambashare "$usuario"
echo "$usuario:1234" | chpasswd  # Establecer una contraseña por defecto (puede cambiarse)
smbpasswd -a "$usuario"  # Agregar el usuario a Samba
smbpasswd -e "$usuario"  # Habilitar el usuario en Samba

#Restart Samba service
systemctl restart smbd
systemctl enable smbd

# Verify Samba Service
if systemctl is-active --quiet smbd; then
    echo "The Samba service is runs correctly."
else
    echo "Samba Server not runs."
    exit 1
fi

# Show the shared folder and configuration
echo "====================================================================================="
echo "======= The shared folder '$carpeta_compartida' has been shared correctly. =========="
echo "============= Shared Folder: //$HOSTNAME/$carpeta_compartida ========================"
echo "====================================================================================="
}

backup_or_restore_backup_from_ssh_server() {


# Log file
LOG_FILE="$HOME/backup.log"

# Function to create a backup
backup() {
    read -r -p "Enter the directory to back up: " BACKUP_DIR
    read -r -p "Enter the local folder to store the backup (If it doesn't exist, it will be created automatically): " DEST_DIR

    if [ ! -d "$BACKUP_DIR" ]; then
        echo "Error: The directory '$BACKUP_DIR' does not exist."
        exit 1
    fi

    mkdir -p "$DEST_DIR"

    BACKUP_FILE="$DEST_DIR/backup_$(date +'%Y%m%d_%H%M%S').tar.xz"

    echo "$(date +"%Y-%m-%d %H:%M:%S") - Starting backup..." | tee -a "$LOG_FILE"
    tar -cJf "$BACKUP_FILE" "$BACKUP_DIR"

    if [ $? -eq 0 ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Backup created: $BACKUP_FILE" | tee -a "$LOG_FILE"
    else
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Error creating the backup" | tee -a "$LOG_FILE"
        exit 1
    fi

    read -r -p "Do you want to send the backup to a remote server? (y/n): " RESPONSE
    if [[ "$RESPONSE" =~ ^[Yy]$ ]]; then
        send_to_remote "$BACKUP_FILE"
    fi
}

# Function to send a file to a remote server
send_to_remote() {
    FILE_TO_SEND="$1"
    read -r -p "Enter the remote server user: " REMOTE_USER
    read -r -p "Enter the remote server IP or domain: " REMOTE_HOST
    read -r -p "Enter the SSH port (Default is 22): " REMOTE_PORT
    read -r -p "Enter the path on the remote server to store the file: " REMOTE_PATH
    
    REMOTE_PORT=${REMOTE_PORT:-22}
    
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Checking connection to $REMOTE_HOST on port $REMOTE_PORT..." | tee -a "$LOG_FILE"
    if ! nc -z "$REMOTE_HOST" "$REMOTE_PORT"; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Error: Could not connect to $REMOTE_HOST on port $REMOTE_PORT." | tee -a "$LOG_FILE"
        exit 1
    fi

    echo "$(date +"%Y-%m-%d %H:%M:%S") - Sending file to $REMOTE_HOST..." | tee -a "$LOG_FILE"
    scp -P "$REMOTE_PORT" "$FILE_TO_SEND" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"
    
    if [ $? -eq 0 ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") - File successfully sent" | tee -a "$LOG_FILE"
    else
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Error sending the file" | tee -a "$LOG_FILE"
    fi
}

# Function to restore a backup from a remote server
restore_backup() {
    read -r -p "Enter the remote server user: " REMOTE_USER
    read -r -p "Enter the remote server IP or domain: " REMOTE_HOST
    read -r -p "Enter the SSH port (Default is 22): " REMOTE_PORT
    read -r -p "Enter the path of the backup file on the remote server: " REMOTE_FILE
    read -r -p "Enter the folder where the backup should be restored: " RESTORE_DIR

    REMOTE_PORT=${REMOTE_PORT:-22}
    
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Downloading backup from $REMOTE_HOST..." | tee -a "$LOG_FILE"
    scp -P "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_FILE" "$HOME"
    
    if [ $? -eq 0 ]; then
        BACKUP_FILENAME=$(basename "$REMOTE_FILE")
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Backup successfully downloaded: $HOME/$BACKUP_FILENAME" | tee -a "$LOG_FILE"

        echo "$(date +"%Y-%m-%d %H:%M:%S") - Restoring backup to $RESTORE_DIR..." | tee -a "$LOG_FILE"
        mkdir -p "$RESTORE_DIR"
        tar -xJf "$HOME/$BACKUP_FILENAME" -C "$RESTORE_DIR"

        if [ $? -eq 0 ]; then
            echo "$(date +"%Y-%m-%d %H:%M:%S") - Restoration completed in $RESTORE_DIR" | tee -a "$LOG_FILE"
        else
            echo "$(date +"%Y-%m-%d %H:%M:%S") - Error restoring the backup" | tee -a "$LOG_FILE"
        fi
    else
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Error downloading the backup" | tee -a "$LOG_FILE"
    fi
}

# Function to download a file from a remote server
download_file() {
    read -r -p "Enter the remote server user: " REMOTE_USER
    read -r -p "Enter the remote server IP or domain: " REMOTE_HOST
    read -r -p "Enter the SSH port (Default is 22): " REMOTE_PORT
    read -r -p "Enter the path of the file on the remote server: " REMOTE_FILE
    read -r -p "Enter the local folder to save the file: " LOCAL_DIR
    
    REMOTE_PORT=${REMOTE_PORT:-22}
    mkdir -p "$LOCAL_DIR"
    
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Downloading file from $REMOTE_HOST..." | tee -a "$LOG_FILE"
    scp -P "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_FILE" "$LOCAL_DIR"
    
    if [ $? -eq 0 ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") - File successfully downloaded to $LOCAL_DIR" | tee -a "$LOG_FILE"
    else
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Error downloading the file" | tee -a "$LOG_FILE"
    fi
}

# Main menu
echo "Select an option:"
echo "1) Create a backup"
echo "2) Restore a backup"
echo "3) Download a file from a remote server"
read -r -p "Enter the option number: " OPTION

case $OPTION in
    1) backup ;;
    2) restore_backup ;;
    3) download_file ;;
    *) echo "Invalid option. Exiting..." ;;
esac

echo "$(date +"%Y-%m-%d %H:%M:%S") - Process completed." | tee -a "$LOG_FILE"

}

# Install and configure SFTP Server

install_ftp_server_over_ssh() {


# Prompt user for input

echo "-----------------------------------------------------------------------------------"
read -p "Enter SFTP group name: " SFTP_GROUP
read -p "Enter SFTP username: " SFTP_USER
read -p "Enter SFTP base directory (e.g., /sftp/$SFTP_USER): " SFTP_DIR
read -s -p "Enter password for $SFTP_USER: " PASSWORD
echo ""
echo "-----------------------------------------------------------------------------------"

# Validate input
if [[ -z "$SFTP_GROUP" || -z "$SFTP_USER" || -z "$PASSWORD" ]]; then
    echo "Error: All fields are required. Please restart the script and provide valid inputs."
    exit 1
fi
SFTP_DIR="${SFTP_DIR:-/sftp/$SFTP_USER}"

# Install OpenSSH if not installed
echo "Installing OpenSSH Server..."
apt update && apt install -y openssh-server || { echo "Failed to install OpenSSH Server"; exit 1; }

# Create SFTP group if it doesn't exist
if ! getent group "$SFTP_GROUP" >/dev/null; then
    echo "Creating group $SFTP_GROUP..."
    groupadd "$SFTP_GROUP" || { echo "Failed to create group"; exit 1; }
else
    echo "Group $SFTP_GROUP already exists."
fi

# Create user without SSH access
if id "$SFTP_USER" &>/dev/null; then
    echo "User $SFTP_USER already exists."
else
    echo "Creating user $SFTP_USER..."
    useradd -m -d "$SFTP_DIR" -s /usr/sbin/nologin -G "$SFTP_GROUP" "$SFTP_USER" || { echo "Failed to create user"; exit 1; }
    echo "$SFTP_USER:$PASSWORD" | chpasswd
fi

# Set permissions
echo "Setting permissions for the SFTP directory..."
mkdir -p "$SFTP_DIR/upload"
chown root:root "$SFTP_DIR"
chmod 755 "$SFTP_DIR"
chown "$SFTP_USER:$SFTP_GROUP" "$SFTP_DIR/upload"
chmod 750 "$SFTP_DIR/upload"

# Configure SSH for SFTP
echo "Configuring SSH for SFTP..."
SSHD_CONFIG="/etc/ssh/sshd_config"
if ! grep -q "Match Group $SFTP_GROUP" "$SSHD_CONFIG"; then
    echo "Match Group $SFTP_GROUP
    ChrootDirectory $SFTP_DIR
    ForceCommand internal-sftp
    X11Forwarding no
    AllowTcpForwarding no" >> "$SSHD_CONFIG"
else
    echo "SFTP configuration for group $SFTP_GROUP already exists in $SSHD_CONFIG."
fi

# Restart SSH service
echo "Restarting SSH service..."
systemctl restart ssh || { echo "Failed to restart SSH service"; exit 1; }

# Final message
echo "SFTP setup complete. User $SFTP_USER can now connect using SFTP."
echo "-----------------------------------------------------------------------------------"
echo "To connect using FileZilla:"
echo "- Host: Your server's IP address"
echo "- Username: $SFTP_USER"
echo "- Password: (the one you set)"
echo "- Port: 22"
echo "- Protocol: SFTP - SSH File Transfer Protocol"
echo "-----------------------------------------------------------------------------------"

}
# function to install Apache, PHP, MySQL server, MySQL client, Certbot, Bind9, Nextcloud, and required configurations to set up the server.

nextcloud_install(){

    echo "==========================================================="
    echo "                   Nextcloud Installation                  "
    echo "==========================================================="
    echo ""

    # Check if the user is root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root." 
        exit 1
    fi

    # Prompt for configuration values
    read -p "Enter the database user name (default: root): " DB_USER
    DB_USER=${DB_USER:-"root"}

    read -p "Enter the database name (default: nextcloud_db): " DB_NAME
    DB_NAME=${DB_NAME:-"nextcloud_db"}

    read -sp "Enter the password for the database user: " DB_PASSWORD
    echo

    read -p "Enter the Nextcloud installation path (default: /var/www/html/nextcloud): " NEXTCLOUD_PATH
    NEXTCLOUD_PATH=${NEXTCLOUD_PATH:-"/var/www/html/nextcloud"}

    read -p "Enter the directory where Nextcloud will store data (default: /var/nextcloud/data): " DATA_DIRECTORY
    DATA_DIRECTORY=${DATA_DIRECTORY:-"/var/nextcloud/data"}

    read -p "Enter the domain or IP to access Nextcloud: " DOMAIN

    # Confirm installation
    echo -e "\n========================================================"
    echo -e "============ Configuration Summary: ===================="
    echo -e "========================================================\n"
    echo "Database: $DB_NAME"
    echo "Database User: $DB_USER"
    echo "Installation Path: $NEXTCLOUD_PATH"
    echo "Data Directory: $DATA_DIRECTORY"
    echo "Domain or IP: $DOMAIN"
    read -p "Do you want to proceed with the installation? (y/n): " CONFIRM
    echo
    if [[ "$CONFIRM" != [yY] ]]; then
        echo "Installation canceled."
        exit 1
    fi

    # Update system packages
    echo "Updating system..."
    apt update && apt upgrade -y

    # Install required software
    echo "Installing Apache, MariaDB, PHP, and required dependencies..."
    apt install -y apache2 mariadb-server php php-cli php-fpm php-gd php-json php-mbstring php-curl php-xml php-zip php-mysql php-intl php-bz2 php-imagick libapache2-mod-php unzip wget lbzip2

    # Configure MariaDB
    echo "Configuring MariaDB..."
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -u root -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
    mysql -u root -e "FLUSH PRIVILEGES;"

    # Configure PHP
    echo "Configuring PHP..."
    PHP_INI_PATH=$(php -r "echo php_ini_loaded_file();")
    if [[ -f "$PHP_INI_PATH" ]]; then
        sed -i "s/memory_limit = .*/memory_limit = 512M/" "$PHP_INI_PATH"
        sed -i "s/upload_max_filesize = .*/upload_max_filesize = 512M/" "$PHP_INI_PATH"
        sed -i "s/post_max_size = .*/post_max_size = 512M/" "$PHP_INI_PATH"
        sed -i "s/max_execution_time = .*/max_execution_time = 300/" "$PHP_INI_PATH"
    fi

    # Download and configure Nextcloud
    echo "Downloading the latest version of Nextcloud..."
    wget https://download.nextcloud.com/server/releases/latest.tar.bz2 -O nextcloud.tar.bz2
    tar -xf nextcloud.tar.bz2
    mv nextcloud "$NEXTCLOUD_PATH"
    chown -R www-data:www-data "$NEXTCLOUD_PATH"
    chmod -R 755 "$NEXTCLOUD_PATH"

    # Create Data Directory
    echo "Creating Data Directory..."
    if [[ ! -d "$DATA_DIRECTORY" ]]; then
        mkdir -p "$DATA_DIRECTORY"
        echo "Data directory created at: $DATA_DIRECTORY"
    else
        echo "Data directory already exists: $DATA_DIRECTORY"
    fi
    chown -R www-data:www-data "$DATA_DIRECTORY"
    chmod -R 750 "$DATA_DIRECTORY"

    # Configure Apache
    echo "Configuring Apache for Nextcloud..."
    cat > /etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:80>
    ServerAdmin admin@$DOMAIN
    DocumentRoot $NEXTCLOUD_PATH
    ServerName $DOMAIN

    <Directory $NEXTCLOUD_PATH>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF

    a2enmod rewrite headers env dir mime
    a2ensite nextcloud
    systemctl restart apache2

    # Finish
    echo "Nextcloud installation complete."
    echo "Please access http://$DOMAIN to complete setup in the browser."
}

moodle_install(){
# Script that configure moodle 

echo "----------------------------------------------"
echo "-------------- MOODLE SETUP ------------------"
echo "----------------------------------------------"

# Prompt for database name
read -p "Enter the database name (default: moodle_db): " DB_NAME
DB_NAME=${DB_NAME:-"moodle_db"}

# Prompt for database user
read -p "Enter the database user name (default: moodle_user): " DB_USER
DB_USER=${DB_USER:-"moodle_user"}

read -p "What will be your data directory? (default: /var/www/moodledata): " data_directory
data_directory=${data_directory:-"/var/www/moodledata"}



# Prompt for database password
read -sp "Enter the password for the database user: " DB_PASSWORD
echo

# Prompt for installation path
read -p "Enter the moodle installation path (default: /var/www/html/moodle): " MOODLE_PATH
MOODLE_PATH=${MOODLE_PATH:-"/var/www/html/moodle"}


# Prompt for domain or IP
read -p "Enter the domain or IP to access Moodle: " DOMAIN


# Configuration confirmation
echo -e ""
echo -e "========================================================"
echo -e "============ Configuration Summary: ===================="
echo -e "========================================================"
echo -e ""

echo "Database: $DB_NAME"
echo "Database User: Root"
echo "Installation Path: $MOODLE_PATH"
echo "Domain or IP: $DOMAIN"
echo "Data Directory: " $data_directory
echo -e "Do you want to proceed with the installation? (y/n): "

# Confirmation to proceed with the installation
read -n 1 CONFIRM
echo
if [[ "$CONFIRM" != [yY] ]]; then
    echo "Installation canceled."
    exit 1
fi

# Rest of the script for Moodle installation
# Update and upgrade packages
echo "========================================================"
echo "=============== Updating system... ====================="
echo "========================================================"
apt update && apt upgrade -y

# Install Apache
echo "Installing Apache..."
apt install apache2 -y
ufw allow 'Apache Full'

# Install MariaDB
echo "Installing MariaDB..."
apt install mariadb-server -y
mysql_secure_installation

# Create database and user for moodle
echo "Configuring database for Moodle.."
mysql -u root -e "CREATE DATABASE ${DB_NAME};"
mysql -u root -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

# Install PHP and necessary modules
echo "Installing PHP  and modules..."
sudo apt install -y php php-gd php-json php-mbstring php-curl php-xml php-zip php-mysql php-intl php-bz2 php-imagick php-fpm php-cli libapache2-mod-php php-sqlite3 php-pgsql git
sudo apt update
sudo apt install php-curl php-zip

# Configure PHP
echo "Configuring PHP..."
PHP_INI_PATH=$(php -r "echo php_ini_loaded_file();")
sed -i "s/memory_limit = .*/memory_limit = 512M/" "$PHP_INI_PATH"
sed -i "s/upload_max_filesize = .*/upload_max_filesize = 512M/" "$PHP_INI_PATH"
sed -i "s/post_max_size = .*/post_max_size = 512M/" "$PHP_INI_PATH"
sed -i "s/max_execution_time = .*/max_execution_time = 300/" "$PHP_INI_PATH"


# Download and configure Nextcloud
echo "Downloading Moodle..."
sudo apt install git
sudo apt install php-xml
sudo apt install php-mbstring
sudo apt install php-mysqli

git clone https://github.com/moodle/moodle.git
mv moodle $MOODLE_PATH
chown -R www-data:www-data $MOODLE_PATH
chmod -R 755 $MOODLE_PATH

# Make the Moodle data directory

mkdir $data_directory
chown -R www-data:www-data $data_directory
chmod -R 755 $data_directory

# Restart Apache web server
systemctl restart apache2

# Finish
echo "---------------------------------------------------------------------"
echo "Moodle installation complete."
echo "Please access http://$DOMAIN/moodle to complete setup in the browser."
echo "---------------------------------------------------------------------"
}
wp_install() {

# Enable strict mode: stop script execution if any command fails
set -e

# Define variables
WP_URL="https://wordpress.org/latest.tar.gz"
WP_ARCHIVE="latest.tar.gz"
WP_DIR="/var/www/html/wordpress"

# Ask user for database details
read -p "Enter the database name: " DB_NAME
read -p "Enter the database username: " DB_USER
read -s -p "Enter the database password: " DB_PASS
echo ""

# Display installation details
echo ""
echo "🔹 WordPress will be installed with the following settings:"
echo "   📂 Download and extraction in: $(pwd)"
echo "   🚀 Installation in: $WP_DIR"
echo "   💾 Database name: $DB_NAME"
echo "   👤 Database user: $DB_USER"
echo ""
read -p "❓ Do you want to continue? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "❌ Installation canceled."
    exit 1
fi

# Update system
echo "🔄 Updating packages..."
sudo apt update && sudo apt upgrade -y

# Install Apache
echo "🌍 Installing Apache..."
sudo apt install -y apache2

echo "💾 Installing MariaDB..."
sudo apt update
sudo apt install -y mariadb-server
sudo systemctl enable --now mariadb

# Configure MARIADB (create DB and user)
echo "🛠 Configuring Mariadb..."
sudo mysql -e "CREATE DATABASE $DB_NAME;"
sudo mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Install PHP and required modules
echo "🐘 Installing PHP and modules..."
sudo apt install -y php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip

# Download and extract WordPress in the script's directory
echo "⬇ Downloading WordPress in $(pwd)..."
wget -q $WP_URL -O $WP_ARCHIVE
tar -xzf $WP_ARCHIVE

# Move WordPress to /var/www/html
echo "📂 Moving WordPress to $WP_DIR..."
sudo mv wordpress $WP_DIR

# Set permissions
echo "🔑 Setting permissions..."
sudo chown -R www-data:www-data $WP_DIR
sudo chmod -R 755 $WP_DIR

# Configure wp-config.php automatically
echo "⚙ Configuring WordPress..."
sudo cp $WP_DIR/wp-config-sample.php $WP_DIR/wp-config.php
sudo sed -i "s/database_name_here/$DB_NAME/" $WP_DIR/wp-config.php
sudo sed -i "s/username_here/$DB_USER/" $WP_DIR/wp-config.php
sudo sed -i "s/password_here/$DB_PASS/" $WP_DIR/wp-config.php

echo "------------------------------------------------------------"
echo "-----------------------------------------"
echo ""
echo "   💾 database name: $DB_NAME"
echo "   👤 database user: $DB_USER"
echo ""
echo "-----------------------------------------"
echo "------------------------------------------------------------"

# Cleanup
echo "🧹 Removing installation archive..."
rm -f $WP_ARCHIVE

echo "✅ Installation complete. Access http://your-server/wordpress to finish WordPress setup."

}

manage_certbot() {


# Function to list installed SSL certificates
list_certificates() {
  echo "Listing installed SSL certificates..."
  certbot certificates || { echo "Failed to list certificates"; exit 1; }
}

# Function to install Certbot and set up a certificate
install_certificate() {
  # Prompt for the domain and email
  read -p "Enter the domain for the SSL certificate: " domain
  read -p "Enter your email address: " email

  # Update repositories and ensure the system is up to date
  echo "Updating repositories and upgrading system..."
  apt update && apt upgrade -y || { echo "Failed to update system"; exit 1; }

  # Install necessary software for Certbot if not already installed
  if ! command -v certbot &> /dev/null; then
    echo "Certbot not found, installing..."
    apt install -y software-properties-common || { echo "Failed to install software-properties-common"; exit 1; }
    add-apt-repository ppa:certbot/certbot -y || { echo "Failed to add Certbot repository"; exit 1; }
    apt update
    apt install -y certbot python3-certbot-nginx python3-certbot-apache || { echo "Failed to install Certbot"; exit 1; }
  else
    echo "Certbot is already installed."
  fi

  # Check if Nginx or Apache is in use
  if systemctl is-active --quiet nginx; then
    web_server="nginx"
  elif systemctl is-active --quiet apache2; then
    web_server="apache2"
  else
    echo "Neither Nginx nor Apache was detected. Ensure you have one of them installed."
    exit 1
  fi

  # Run Certbot to obtain the SSL certificate based on the web server
  echo "Obtaining SSL certificate for $domain using $web_server..."
  if [ "$web_server" == "nginx" ]; then
    certbot --nginx -d "$domain" --agree-tos --no-eff-email --email "$email" || { echo "Failed to obtain SSL certificate for Nginx"; exit 1; }
  elif [ "$web_server" == "apache2" ]; then
    certbot --apache -d "$domain" --agree-tos --no-eff-email --email "$email" || { echo "Failed to obtain SSL certificate for Apache"; exit 1; }
  fi

  # Set up automatic certificate renewal
  echo "Setting up automatic renewal..."
  systemctl enable certbot.timer || { echo "Failed to enable certbot.timer"; exit 1; }
  systemctl start certbot.timer || { echo "Failed to start certbot.timer"; exit 1; }

  echo "SSL certificate successfully installed for $domain."
}

# Menu options
echo "Select an option:"
echo "1. Install Certbot and set up an SSL certificate"
echo "2. List installed SSL certificates"
read -p "Option: " option

case $option in
  1)
    install_certificate
    ;;
  2)
    list_certificates
    ;;
  *)
    echo "Invalid option. Exiting..."
    exit 1
    ;;
esac
}

configure_prometheus () {


# Variables
PROM_VERSION="2.51.2"
PROM_USER="prometheus"
PROM_DIR="/etc/prometheus"
PROM_DATA_DIR="/var/lib/prometheus"
PROM_BIN_DIR="/usr/local/bin"
NODE_EXPORTER_VERSION="1.7.0"

install_prometheus() {
    echo "Updating system and installing dependencies..."
    apt update && apt install -y wget tar || { echo "Failed to install dependencies"; exit 1; }
    
    echo "Creating Prometheus user..."
    useradd --no-create-home --shell /bin/false $PROM_USER
    
    echo "Creating directories..."
    mkdir -p $PROM_DIR $PROM_DATA_DIR
    chown $PROM_USER:$PROM_USER $PROM_DIR $PROM_DATA_DIR
    
    echo "Downloading Prometheus v$PROM_VERSION..."
    wget https://github.com/prometheus/prometheus/releases/download/v$PROM_VERSION/prometheus-$PROM_VERSION.linux-amd64.tar.gz -O /tmp/prometheus.tar.gz
    
    echo "Extracting Prometheus..."
    tar -xzf /tmp/prometheus.tar.gz -C /tmp/
    cd /tmp/prometheus-$PROM_VERSION.linux-amd64/
    
    echo "Installing Prometheus binaries..."
    mv prometheus promtool $PROM_BIN_DIR/
    chown $PROM_USER:$PROM_USER $PROM_BIN_DIR/prometheus $PROM_BIN_DIR/promtool
    
    echo "Setting up configuration..."
    mv prometheus.yml $PROM_DIR/
    chown $PROM_USER:$PROM_USER $PROM_DIR/prometheus.yml
    
    echo "Creating Prometheus systemd service..."
    cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus Monitoring System
Wants=network-online.target
After=network-online.target

[Service]
User=$PROM_USER
Group=$PROM_USER
Type=simple
ExecStart=$PROM_BIN_DIR/prometheus \\
    --config.file=$PROM_DIR/prometheus.yml \\
    --storage.tsdb.path=$PROM_DATA_DIR \\
    --web.listen-address=0.0.0.0:9090 \\
    --storage.tsdb.retention.time=15d

[Install]
WantedBy=multi-user.target
EOF
    
    echo "Starting Prometheus service..."
    systemctl daemon-reload
    systemctl enable --now prometheus.service
    echo "Prometheus installation complete! Running on port 9090"
    echo "Directory of prometheus: $PROM_DIR"
}

install_node_exporter() {


set -e  # Stop script on error

# Update the system
sudo apt update && sudo apt upgrade -y

# Install required dependencies
sudo apt install -y wget tar curl

# Get the latest Node Exporter version dynamically
NODE_EXPORTER_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep -oP '"tag_name": "v\K[0-9.]+')

# Check if Node Exporter is already installed
if command -v node_exporter &> /dev/null; then
    echo "Node Exporter is already installed. Skipping installation."
    exit 0
fi

# Download Node Exporter
wget https://github.com/prometheus/node_exporter/releases/download/v$NODE_EXPORTER_VERSION/node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz

# Extract the downloaded file
tar -xvzf node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz

# Move the binary to /usr/local/bin
sudo mv node_exporter-$NODE_EXPORTER_VERSION.linux-amd64/node_exporter /usr/local/bin/

# Remove downloaded files to save space
rm -rf node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz node_exporter-$NODE_EXPORTER_VERSION.linux-amd64

# Ensure the user exists
if ! id "node_exporter" &>/dev/null; then
    sudo useradd -rs /bin/false node_exporter
fi

# Create a systemd service for Node Exporter
cat << EOF | sudo tee /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF

# Reload systemd daemon and enable the service
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

# Check if Node Exporter is running
sudo systemctl status node_exporter --no-pager

echo "-----------------------------------"
echo " ✅ Node Exporter installed and running on port 9100"
echo "-----------------------------------"

}

add_node_exporter_to_prometheus() {
    read -p "Enter the IP address of the Node Exporter: " NODE_EXPORTER_IP
    read -p "Enter the job name for Node Exporter: " JOB_NAME
    echo "Adding Node Exporter job to prometheus.yml..."
    cat <<EOF >> $PROM_DIR/prometheus.yml

  - job_name: '$JOB_NAME'
    static_configs:
      - targets: ['$NODE_EXPORTER_IP:9100']
EOF
    echo "Node Exporter job '$JOB_NAME' added to Prometheus configuration. Restarting Prometheus..."
    systemctl restart prometheus.service
}

# Menu for installation
echo "--------------------------------------------------"
echo "Choose an option:"
echo "1) Install Prometheus"
echo "2) Install Node Exporter"
echo "3) Add Node Exporter to Prometheus"
echo "4) Exit"
echo "--------------------------------------------------"
read -p "Enter your choice: " CHOICE

case $CHOICE in
    1)
        install_prometheus
        ;;
    2)
        install_node_exporter
        ;;
    3)
        add_node_exporter_to_prometheus
        ;;
    4)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo "Invalid choice. Exiting..."
        exit 1
        ;;
esac


# Final message
echo "--------------------------------------------------"
echo "Installation process complete!"
echo "--------------------------------------------------"

}
configure_graphana () {

# Starting message
echo "Starting Grafana installation."

# Update system repositories
echo "Updating system repositories..."
apt update && apt upgrade -y

# Install necessary dependencies
echo "Installing necessary dependencies..."
apt install -y software-properties-common wget

# Add the official Grafana repository
echo "Adding the official Grafana repository..."
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list

# Update repositories after adding Grafana
echo "Updating repositories after adding Grafana..."
apt update

# Install Grafana
echo "Installing Grafana..."
apt install -y grafana

# Verify installation
if [ $? -eq 0 ]; then
    echo "Grafana installed successfully."
else
    echo "There was a problem installing Grafana. Please check the errors."
    exit 1
fi

# Start and enable the Grafana service
echo "Starting the Grafana service..."
systemctl start grafana-server
systemctl enable grafana-server

# Verify the status of Grafana
echo "Checking the Grafana service status..."
systemctl status grafana-server --no-pager | grep -i 'active'

# Final message
echo "----------------------------------------------------------------------------------"
echo "Grafana has been successfully installed on the server!"
echo "You can access the Grafana web interface at http://<YOUR-SERVER-IP>:3000."
echo "Default username: admin"
echo "Default password: admin"

# Warning message for first login
echo "Remember to change the password on the first login."
echo "-----------------------------------------------------------------------------------"

}

setup_virtualhost () {


# Ask user for domain name
read -p "Enter your domain name: " DOMAIN

# Ask user for document root
read -p "Enter your document root (default: /var/www/html/$DOMAIN): " DOC_ROOT
DOC_ROOT=${DOC_ROOT:-/var/www/html/$DOMAIN}

# Ask user if they want SSL
read -p "Do you want to enable SSL? (y/n): " ENABLE_SSL
CONFIG_FILE=/etc/apache2/sites-available/$DOMAIN.conf
SSL_CONFIG_FILE=/etc/apache2/sites-available/$DOMAIN-ssl.conf

sudo chown -R $USER:$USER $DOC_ROOT
sudo chmod -R 755 /var/www/html

# Create virtual host configuration
sudo tee $CONFIG_FILE > /dev/null <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@$DOMAIN
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot $DOC_ROOT
    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-access.log combined
</VirtualHost>
EOF

# Enable SSL if chosen
if [ "$ENABLE_SSL" == "y" ]; then
    sudo tee $SSL_CONFIG_FILE > /dev/null <<EOF
<VirtualHost *:443>
    ServerAdmin webmaster@$DOMAIN
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot $DOC_ROOT
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/$DOMAIN.crt
    SSLCertificateKeyFile /etc/ssl/private/$DOMAIN.key
    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-ssl-access.log combined
</VirtualHost>
EOF
    sudo a2enmod ssl
    sudo a2ensite $DOMAIN-ssl.conf
fi

# Enable the site and reload Apache
sudo a2ensite $DOMAIN.conf
sudo systemctl reload apache2

# Output success message
echo "Virtual host for $DOMAIN has been created successfully!"
if [ "$ENABLE_SSL" == "y" ]; then
    echo "SSL has been enabled for $DOMAIN. Make sure to place your certificate files in /etc/ssl/certs/ and /etc/ssl/private/."
fi
}

network_scan() {

# Function to scan the local network and display connected devices
scan_network() {

      #show interfaces
            echo ""
            echo "++++++++++++++++++++++++++++++++"
            echo "Available interfaces"
            echo "++++++++++++++++++++++++++++++++"
            INTERFACES=$(ip link show | awk -F': ' '{print $1,  $2}')
            echo "$INTERFACES"
            echo "++++++++++++++++++++++++++++++++"
            echo ""
            read -p "What interface wwould use to scan: " interface

    echo "Scanning devices on the local network using interface $interface..."
    echo ""

    # Use arp-scan to get connected devices
    if command -v arp-scan > /dev/null 2>&1; then
        sudo arp-scan --interface="$interface" --localnet
    else
        echo "arp-scan is not installed. Installing it..."
        sudo apt update && sudo apt install -y arp-scan
        sudo arp-scan --interface="$interface" --localnet
    fi
}

# Interactive menu
while true; do
    echo ""
    echo "--- Connected Devices Scan ---"
    echo "1. Scan the local network"
    echo "2. Exit"
    read -p "Select an option: " option

    case $option in
        1) scan_network ;;
        2) echo "Exiting..."; exit 1 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
done
}

show_system_info () {
# Show a welcome message
echo "*******************************************************************"
echo "****** MONITORING CPU, MEMORY, DISK AND NETWORK INFORMATION *******"
echo "*******************************************************************"

echo "To run this script successfully, please ensure 'curl' is installed. You can install it using: 'snap install curl' or 'apt install curl'"
echo

# Function to get the hostname
get_HOSTNAME() {
    HOSTNAME=$(cat /etc/hostname)
}

# Function to get CPU usage
get_cpu_usage() {
    echo "CPU USAGE:"
    top -bn1 | grep "Cpu(s)" | awk '{printf "CPU in use: %.2f%%\n", $2 + $4}'
}

# Function to get memory usage in GB
get_memory_usage() {
    echo "MEMORY USAGE:"
    free -m | grep Mem | awk '{printf "Memory used: %.2fGB of %.2fGB\n", $3/1024, $2/1024}'
}

# Function to get disk usage
get_disk_usage() {
    echo "DISK USAGE:"
    df -h / | grep / | awk '{print "Disk usage: " $5 " (" $3 " used of " $2 ")"}'
}

# Function to get swap memory usage
get_swap_usage() {
    echo "SWAP USAGE:"
    free -m | grep Swap | awk '{printf "Swap used: %.2fGB of %.2fGB\n", $3/1024, $2/1024}'
}

# Function to get the network interface in use
get_network_interface() {
    interfaz=$(ip route | grep '^default' | awk '{print $5}')
    if [[ -z "$interfaz" ]]; then
        echo "A network interface could not be detected."
        return 1
    fi
    echo "Your network interface is: $interfaz"
}

# Function to get local IP
get_local_ip() {
    echo "LOCAL IP:"
    hostname -I
}

# Function to get MAC address
get_DIR_MAC() {
    echo "MAC ADDRESS:"
    interfaz=$(ip route | grep '^default' | awk '{print $5}')
    cat /sys/class/net/$interfaz/address
}

# Function to get the default gateway
get_DEFAULT_GATEWAY() {
    echo "DEFAULT GATEWAY:"
    ip route show default
}

# Function to get the public IP
get_public_ip() {
    echo "PUBLIC IP:"
    PUBLIC_IP=$(curl -s ifconfig.me)
    if [[ -n "$PUBLIC_IP" ]]; then
        echo "Public IP: $PUBLIC_IP"
    else
        echo "Could not obtain your Public IP Address. Check your Internet connection."
    fi
}

# Function to check internet connection
get_INTERNET_CONNECTION() {
    echo "INTERNET CONNECTION:"
    var=$(curl -s --head http://www.google.com | head -n 1)
    if [[ $var == *"200 OK"* ]]; then
        echo "Internet Connection: Active"
    else
        echo "No internet connection detected. Please check your network adapter and rerun the script."
    fi
}

# Get system information
echo "-----------------------------------"
echo "The Hostname of the system is: $HOSTNAME"
echo "-----------------------------------"
get_cpu_usage
echo "-----------------------------------"
get_memory_usage
echo "-----------------------------------"
get_disk_usage
echo "-----------------------------------"
get_swap_usage
echo "-----------------------------------"
get_network_interface
echo "-----------------------------------"
get_local_ip
echo "-----------------------------------"
get_DIR_MAC
echo "-----------------------------------"
get_DEFAULT_GATEWAY
echo "-----------------------------------"
get_public_ip
echo "-----------------------------------"
get_INTERNET_CONNECTION
echo "-----------------------------------"

}


# Main Menu
while true; do

    echo "==================================================================="
    echo "========================= ZenNet Forge ============================"
    echo "==================================================================="
    echo "====================== by: TheHellishPandaa ======================="
    echo "==================== GitHub: TheHellishPandaa ====================="
    echo "==================================================================="
    echo ""
    echo "1) Configure network interfaces"
    echo "2) Configure gateway server"
    echo "3) Configure DHCP server"
    echo "4) Install forwarder + cache DNS "
    echo "5) Change FQDN Name"
    echo "6) Configure SAMBA server"
    echo "7) Configure FTP server over SSH"
    echo "8) Configure Firewall"
    echo "9) Install Nextcloud latest version"
    echo "10) Install Moodle Latest Version"
    echo "11) Install Wordpress"
    echo "12) VirtualHost Setup"
    echo "13) Network Scan"
    echo "14) Install & Configure Prometheus "
    echo "15) Install Graphana "
    echo "16) Show system Informaton "
    echo "17) Configure ACL "
    echo "18) Cerbot Management "
    echo "19) Make Backup or restore backup from ssh server "
    echo "20) Exit"
    read -p "Choose an option: " opcion

    # case for execute the fuctions
    case $opcion in
        1) configure_network ;;
        2) configure_gateway_server ;;
        3) configure_dhcp_server ;;
	4) install_forwarder_dns ;;
        5) configure_fqdn_name ;;
        6) install_samba_server ;;
        7) install_ftp_server_over_ssh ;;
        8) configure_firewall ;;
        9) nextcloud_install ;;
        10) moodle_install ;;
	11) wp_install ;;
 	12) setup_virtualhost ;;
        13) network_scan ;;
	14) configure_prometheus ;;
 	15) configure_graphana ;;
  	16) show_system_info ;;
   	17) configure_acl ;;
        18) manage_certbot ;;
	19) backup_or_restore_backup_from_ssh_server ;;
        20) echo "Exiting. Goodbye!"; break ;;
        *) echo "Invalid option." ;;
    esac
done
