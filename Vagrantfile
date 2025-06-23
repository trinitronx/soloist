# -*- mode: ruby -*-
# vi: set ft=ruby :
# frozen_string_literal: true

Vagrant.configure('2') do |config| # rubocop:disable Metrics/BlockLength
  # Only NFSv3 working w/o hostname + idmapd.conf Domain set
  # config.vm.box = 'bento/ubuntu-22.04'
  # NFSv4 via cloud-init seed ISO
  config.vm.box = 'cloud-image/ubuntu-24.04'
  config.vm.hostname = 'vagrant.internal'
  config.vm.cloud_init_first_boot_only = false

  config.vm.provider :libvirt do |libvirt|
    libvirt.driver = 'kvm' if File.exist?('/dev/kvm')
    libvirt.uri = 'qemu:///system'
    libvirt.system_uri = 'qemu:///system'
    # libvirt.uri = 'qemu+tls://saturn.internal/system'
    # libvirt.system_uri = 'qemu+tls://saturn.internal/system'
    libvirt.machine_type = 'q35'
    libvirt.memory = '2048'
    libvirt.cpus = 2
    libvirt.disk_driver_opts = { cache: 'writeback', io: 'threads', discard: 'unmap', detect_zeroes: 'unmap' }
    # UEFI boot w/Tianocore edk2
    libvirt.loader = '/usr/share/edk2/x64/OVMF_CODE.4m.fd'
    libvirt.nvram_template = '/usr/share/edk2/x64/OVMF_VARS.4m.fd'
    # Use .internal TLD for management network domain
    # References:
    #   - https://www.icann.org/en/board-activities-and-meetings/materials/approved-resolutions-special-meeting-of-the-icann-board-29-07-2024-en#section2.a
    #   - https://datatracker.ietf.org/doc/draft-davies-internal-tld/
    libvirt.management_network_domain = 'internal'

    libvirt.storage :file, device: :cdrom, type: 'qcow2',
                           path: File.expand_path('./test/fixtures/cloud-init-seed.iso.qcow2', __dir__),
                           bus: 'sata'
  end
  # For Vagrant VM network LAN only, no NAT or else the box becomes multi-homed
  # with managment network + this one. 2 default routes are added after reboot
  config.vm.network :private_network, type: 'dhcp', autostart: true, libvirt__forward_mode: 'none'

  # config.vm.synced_folder ".", "/vagrant", type: 'nfs', nfs_version: 3, nfs_udp: false, nfs_export: true
  # Note: NFSv4 does not squash root to anonuid=1000 properly for files with 600 access on bento/ubuntu-22.04
  # This is because the NFSv4 client used Domain = 'localdomain' by default which did not match the host's domain
  # NFSv4 mounts will happen over the management network, so set idmapd.conf Domain accordingly
  # Also set NFSv4 root export with fsid=0 to use 'anonuid=1000,anongid=1000'
  # for the management network subnet in /etc/exports or /etc/exports.d/
  config.vm.synced_folder '.', '/vagrant', type: 'nfs', nfs_version: 4, nfs_udp: false, nfs_export: true
  config.vm.communicator = 'ssh'

  config.vm.provision 'shell', inline: 'test -d /etc/skel/.ssh || mkdir /etc/skel/.ssh'

  # Wait for cloud-init to finish
  config.vm.provision 'shell', inline: 'cloud-init status --wait'

  config.vm.provision 'shell' do |shell|
    shell.path = File.expand_path('script/bootstrap.sh', __dir__)
    shell.args = '$SUDO_USER'
  end
  # install .ruby-version @ .ruby-gemset
  ruby_version = File.open('.ruby-version', 'r').read.chomp
  ruby_gemset = File.open('.ruby-gemset', 'r').read.chomp
  config.vm.provision 'shell',
                      inline: "bash -lc \\
                        'rvm use --install --default ruby-#{ruby_version}; \\
                        rvm gemset create #{ruby_gemset}'",
                      privileged: false
  config.vm.provision 'shell',
                      inline: "bash -lc \\
                        'cd /vagrant/ && \\
                        gem install \"bundler:$(grep -A 1 \"BUNDLED WITH\" Gemfile.lock | tail -n 1)\"'",
                      privileged: false

  # Use separate bundler config inside Vagrant VM
  config.vm.provision 'shell' do |shell|
    shell.path = File.expand_path('script/ci-bundle-config.sh', __dir__)
    shell.args = '$SUDO_USER'
  end

  # Bundle install as user via rvm
  config.vm.provision 'shell',
                      inline: "bash -lc \\
                        'cd /vagrant/ && bundle config set --local frozen true'",
                      privileged: false
  config.vm.provision 'shell',
                      inline: "bash -lc \\
                        'cd /vagrant/ && bundle install'",
                      privileged: false
  # accept + persist chef license accept for non-interactive CI
  config.vm.provision 'shell',
                      inline: "bash -lc \\
                        'cd /vagrant/ && \\
                        rvmsudo bundle exec chef-solo --chef-license accept --local-mode --no-listen --why-run'",
                      privileged: false
  # Run the ci script
  config.vm.provision 'shell',
                      inline: "bash -lc \\
                        'cd /vagrant/ && ./script/ci.sh'",
                      privileged: false
  # Install no-op test fixture cookbook ckbk
  # NOTE: Librarian::Chef::Cli.new.install() suffers from a race condition
  #       Thus, cookbook files may still be in the process of writing
  #       while soloist tries to access them
  # So, we must manually run it first... redundantly
  config.vm.provision 'shell', inline: "bash -lc \\
                                 'cd /vagrant/test/fixtures && bundle exec berks install'",
                               privileged: false
  # Run soloist integration test against fixtures
  config.vm.provision 'shell', inline: "bash -lc \\
                                 'cd /vagrant/test/fixtures && rvmsudo bundle exec soloist'",
                               privileged: false
end
