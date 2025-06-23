#!/bin/bash -l

user=$1;

if [[ ! -e /etc/profile.d/ci-bundler.sh ]] ; then
  user_home="$(getent passwd "${user}" | cut -d: -f 6)"
  echo "export BUNDLE_APP_CONFIG='${user_home}/.bundle'" > /etc/profile.d/ci-bundler.sh
  sync /etc/profile.d/ci-bundler.sh
  mkdir -p "${user_home}/.bundle"
  touch "${user_home}/.bundle/config"
  chown -R "${user}:${user}" "${user_home}/.bundle"
  # Install gems to local CI user's .bundle dir
  sudo -u "$user" bash -lc "bundle config set --local path ${user_home}/.bundle/vendor/bundle"
  sudo -u "$user" bash -lc "bundle config set --local deployment true"
fi

# Note: removing files as root in VM is not allowed by NFS uid mapping
#       Instead, just rely on the anonuid/anongid mapping to uid 1000
if [[ -e '/vagrant/.bundle' ]]; then
  if [[ -L '/vagrant/.bundle' ]]; then
    sudo -u "$user" rm -f '/vagrant/.bundle'
  else
    sudo -u "$user" rm -rf '/vagrant/.bundle'
  fi
fi
