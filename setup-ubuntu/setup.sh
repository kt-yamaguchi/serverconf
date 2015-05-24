#!/bin/bash

check_linux(){
  echo -n "Checking OS : "
  if [ `uname` != 'Linux' ]; then
    echo 'This script could be execute under Linux Environment.'
    exit 1
  fi
  echo "Running with `uname`"
}

check_bash(){
  echo -n "Checking Shell : "
  if [ `readlink /proc/$$/exe` = '/bin/bash' ]; then
    echo 'Running with bash.'
    return 0
  fi
  echo 'This script reqires running with bash.'
  exit 2
}

check_root(){
  echo -n "Checking User : "
  if [ ${EUID:-${UID}} -ne 0 ]; then
    echo 'This script requires root privilege.'
    exit 3
  fi
  echo "This script running as root."
}

check_exist_file(){
  fname=$1
  if [ -e $fname ];then
    echo "${fname} is exist."
    return 0
  fi
  echo "${fname} is not exist."
  exit 4
}

set -e
cd `dirname $0`

check_linux
check_bash
check_root

echo "Checking required files... : "
check_exist_file ./files/smb.conf
check_exist_file ./files/find_sshkey.sh
check_exist_file ./files/mkhomedir
echo "OK."


# At first, security update.
aptitude update
aptitude safe-upgrade -R

# Install some packages
aptitude install -R ssh zsh vim debconf-utils
rm /etc/skel/.bash* || true
touch /etc/skel/.zshrc

# Settings Kerberos configuration
echo "krb5-config     krb5-config/read_conf   boolean true" | debconf-set-selections
echo "krb5-config     krb5-config/add_servers_realm   string  LOCAL.BGP.NE.JP" | debconf-set-selections
echo "krb5-config     krb5-config/admin_server        string local.bgp.ne.jp" | debconf-set-selections
echo "krb5-config     krb5-config/add_servers boolean true" | debconf-set-selections
echo "krb5-config     krb5-config/kerberos_servers    string local.bgp.ne.jp" | debconf-set-selections
echo "krb5-config     krb5-config/default_realm       string  LOCAL.BGP.NE.JP" | debconf-set-selections

# Install AD-related packages
aptitude install -R krb5-config winbind libnss-winbind libpam-winbind

# Disabled smbd
sed -i "s/^start/#start/g" /etc/init/smbd.conf

# Get Samba Configuration
cat ./files/smb.conf > /etc/samba/smb.conf

# Join to AD
net ads join -U Administrator

# Update nsswitch.conf
grep winbind /etc/nsswitch.conf || sed -i "s/compat/compat winbind/g" /etc/nsswitch.conf

# Update PAM configuration
cp ./files/mkhomedir /usr/share/pam-configs/mkhomedir
pam-auth-update

# Enable for serveradmins
echo "%serveradmins ALL=(ALL) ALL" > /etc/sudoers.d/serveradmins

# Install SSH public key retrieve script
cp ./files/find_sshkey.sh /usr/local/sbin/
chmod 700 /usr/local/sbin/find_sshkey.sh

echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
echo "AuthorizedKeysCommand /usr/local/sbin/find_sshkey.sh" >> /etc/ssh/sshd_config
echo "AuthorizedKeysCommandUser root" >> /etc/ssh/sshd_config
echo "Match user nocopsadm" >> /etc/ssh/sshd_config
echo "    PasswordAuthentication yes" >> /etc/ssh/sshd_config

restart winbind
restart ssh
