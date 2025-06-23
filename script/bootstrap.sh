#!/bin/bash

set -e
export DEBIAN_FRONTEND=noninteractive

echo "Updating package list"
sudo apt-get update > /dev/null

echo "Ensuring curl is available"
sudo apt-get install -y curl > /dev/null

echo "Setting up RVM"

user=$1
[ -z "$user" ] && user="ubuntu"

grep "^$user:" /etc/passwd > /dev/null || sudo useradd -m $user -G sudo,rvm,admin -s /bin/bash
sudo sync /etc/passwd

user_home="$(getent passwd "${user}" | cut -d: -f 6)"

curl -sSL https://rvm.io/mpapis.asc | sudo -u "$user" gpg --import -
curl -sSL https://rvm.io/pkuczynski.asc | sudo -u "$user" gpg --import -
test -d "${user_home}/.rvm" || curl -sSL https://get.rvm.io | sudo -u "$user" bash -s stable

test -e "/etc/profile.d/rvm.sh" || sudo tee /etc/profile.d/rvm.sh > /dev/null <<RVMSH_CONTENT
[[ -s "${user_home}/.rvm" ]] && source "${user_home}/.rvm/scripts/rvm"
RVMSH_CONTENT

test -x "/etc/profile.d/rvm.sh" || sudo chmod +x /etc/profile.d/rvm.sh && sudo sync /etc/profile.d/rvm.sh

grep -q 'rvm_gemset_create_on_use_flag' /etc/rvmrc || sudo tee /etc/rvmrc > /dev/null <<RVMRC_CONTENTS
umask u=rwx,g=rwx,o=rx
rvm_install_on_use_flag=1
rvm_trust_rvmrcs_flag=1
rvm_gemset_create_on_use_flag=1
export rvmsudo_secure_path=0
RVMRC_CONTENTS
sync /etc/rvmrc

echo "Detecting RVM requirements"

packages="build-essential openssl libreadline8 libreadline-dev curl git-core
          zlib1g zlib1g-dev libssl-dev libyaml-dev libsqlite3-dev sqlite3
          libxml2-dev libxslt-dev autoconf libc6-dev libgdbm-dev
          ncurses-dev automake libtool bison subversion pkg-config libffi-dev
          libcurl4-openssl-dev libncurses5-dev libgmp-dev"

echo "Detected RVM requirements: $packages"

selections=`dpkg --get-selections`
for package in $packages
do
  if ! echo "$selections" | grep "^$package\s" > /dev/null
  then
    to_install="$to_install $package"
  fi
done

if [ -z "$to_install" ]
then
  echo "Satisfied RVM requirements"
else
  echo "Installing missing RVM requirements: $to_install"
  sudo apt-get --no-install-recommends install -y $to_install
fi

# Reference: https://rvm.io/integration/sudo
echo "Enabling rvm sudo"
echo -e 'Defaults\tenv_keep +="rvm_bin_path GEM_HOME IRBRC MY_RUBY_HOME rvm_path rvm_prefix rvm_version GEM_PATH rvmsudo_secure_path RUBY_VERSION rvm_ruby_string rvm_delete_flag BUNDLE_APP_CONFIG"' \
  | sudo tee /etc/sudoers.d/rvm > /dev/null
sudo sed -i -e '/^Defaults[[:space:]]secure_path=.*/d' /etc/sudoers

# Vagrant/CI user sudo is aliased to rvmsudo
#echo "Enabling sudo=rvmsudo alias for ~${user}/.profile"
#user_home="$(eval echo ~${user})"  ## Note: insecure, but who cares... it's CI!
#[ -e "${user_home}/.profile" ] || touch "${user_home}/.profile"
#if ! grep -q 'alias sudo=rvmsudo' "${user_home}/.profile"; then
#  echo 'alias sudo=rvmsudo' | sudo tee -a "${user_home}/.profile" > /dev/null
#  sync "${user_home}/.profile"
#fi
