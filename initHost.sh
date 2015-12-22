#!/bin/bash

# ==============================================================================
# PRESET VARIABLES
# ==============================================================================

ansible_public_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDGz+lt4PI57xBr49jzPVdclWzGufoEkthsEzc+lZtDi+u4U5pc3SarDhnBywjHX+qYVn90L3c6NgSfOqVuT0tUtT6LDC+LXurXa2jtE6tR4M+cYJrIm3eI/w+PXb2lJP3ChC/HfkM4ooBQGIdrm3ljVVGd86XGViU3l+2vJVl95KPowS+nNNR8gHMTfTZuivogl92xLUU71o/fkXX6QPb9RF7T+JQ3I2/fVNmTQnZzgZkaVEUhfdxEhFH3TLWcx9c5uP48KJ5rmbTwBG9ZRBJ+o9tefgEitC2eiBPKBXJs/n1ZNgxHwR7ipfy51N09NZGVfFAx96wKPySDEWO8hSRN leo@leopad"
default_dns="8.8.8.8 8.8.4.4"
default_domain="newfairs-inc.com"
net_feature="app"
net_tier="staging"

# ==============================================================================
# FUNCTIONS
# ==============================================================================

# arguments: description, default value
# example: confirm_variable "IP address" $current_ip
confirm_variable()
{
  while true; do
    read -p "Please specify your $1 [$2]: " return_confirmed
    if [[ -z $return_confirmed ]]; then
      return_confirmed=$2
    fi
    if [[ ! -z $return_confirmed ]]; then
      break
    fi
    echo "Please specify a non-empty falue for $1."
  done
}

# arguments: case, string (0 for lowercase, 1 for uppercase)
# example: convert_case 0 $string
convert_case()
{
  if [ $1 = 1 ] || [ $1 = "lo" ]; then
    echo $(echo $2 | tr '[A-Z]' '[a-z]')
  else
    echo $(echo $2 | tr '[a-z]' '[A-Z]')
  fi
}

# ---------------------------------------------------------
# STEP 1:
# IP Configuration (Qing Cloud)

# ---------------------------------------------------------
# STEP 2:
# DNS Server

dns_config_file=/etc/resolvconf/resolv.conf.d/head
IFS=';' read -ra net_dns4_list <<< "$default_dns"
for i in "${ADDR[@]}"; do
  echo "nameserver $i" >> dns_config_file
done
resolvconf -u

echo "Successfully updated DNS Server..."
echo

# ---------------------------------------------------------
# STEP 3:
# Set up hostname

# net_tier
echo
confirm_variable "feature of the machine" $net_tier
net_tier=$return_confirmed

# net_feature
echo
confirm_variable "feature of the machine" $net_feature
net_feature=$return_confirmed

# net_ip4
IFS=$'\r\n' GLOBIGNORE='*' :
net_network_device=($(ifconfig | grep eth | awk '{ print $1}'))
net_ip4=$(ifconfig $net_network_device | grep 'inet addr' | cut -d: -f2 | awk '{print $1}');

net_hostname=$(convert_case lo $net_tier)-$(convert_case lo $net_feature)
net_hostname=$net_hostname-$(echo $net_ip4 | sed -r 's/(\.)/-/g').$default_domain

# update hostname
echo "$net_hostname" > /etc/hostname
hostname -F /etc/hostname

# update dhcp config
sed -i.bak -r -e "s/^SET_HOSTNAME.*/#&/" /etc/default/dhcpcd

# update host file
echo "$net_ip4  $net_hostname" >> /etc/hosts

echo "Successfully updated hostname..."
echo

# ---------------------------------------------------------
# STEP 4:
# Apt-get dependiencies.

dependencies="net-tools openssh-client openssh-server"
apt-get -y update
apt-get -y upgrade
apt-get clean
apt-get -y install $apt_dependencies

echo "Successfully updated dependencies..."
echo

# ---------------------------------------------------------
# STEP 5:
# Ansible User

# add ansible user
useradd ansible

# ad ssh key
mkdir -p /home/ansible/.ssh
echo $ansible_public_key > /home/ansible/.ssh/authorized_keys

# chown
chown -R ansible /home/ansible

# sudo
sed -i.bak -r 's/(^root.*)/&\nansible\tALL=(ALL)\tNOPASSWD:ALL/' /etc/sudoers
chmod 440 /etc/sudoers

echo "Successfully added ansible user..."
echo

# ---------------------------------------------------------
# STEP 6:
# Set up SSHD Permissions

# SSHD set up is mandatory.
sshd_config_file=/etc/ssh/sshd_config

# attempt to modify in situ first.
sed -i.bak -r -e "s/^\s*#*\s*PermitRootLogin [a-z\-]*/PermitRootLogin no/" \
              -e "0,/PermitRootLogin no/! s/PermitRootLogin no/#deleted/" \
              -e "s/^\s*#*\s*PasswordAuthentication [a-z\-]*/PasswordAuthentication no/" \
              -e "0,/PasswordAuthentication no/! s/PasswordAuthentication no/#deleted/" \
              -e "/^#deleted/ D" $sshd_config_file

# reject root login if not set
if ! grep -xq '^PermitRootLogin no' $sshd_config_file; then
  echo >> $sshd_config_file
  echo "# Reject root login" >> $sshd_config_file
  echo "PermitRootLogin no" >> $sshd_config_file
fi

# reject password authentication if not set
if ! grep -xq '^PasswordAuthentication no' $sshd_config_file; then
  echo >> $sshd_config_file
  echo "# Reject password authentication" >> $sshd_config_file
  echo "PasswordAuthentication no" >> $sshd_config_file
fi

echo "Successfully revised SSHD permissions..."
echo
service ssh restart

