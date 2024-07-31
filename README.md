# pve-vm-cloudinit

This is a Bash script with a set of commands that
help manage the QEMU VM lifecycle on Proxmox VE nodes for
cloud-init VM templates with customized cloud-init configs.

## Disclaimer

I use these scripts on my single homelab node (v8.2.4).

Feel free to use them at your own risk.

## Reasoning

### Reasoning for cloud-init on Proxmox

> For cloud users, `cloud-init` provides
no-install first-boot configuration management of a cloud instance.

The use of cloud-init in Proxmox allows for
quick and mostly hands-free configuration of
a VM's OS on first boot.
Importantly,
cloud-init does not necessarily need to be deployed to any "cloud",
but any host with the correct hardware and configurations will do.

Proxmox automatically generates some important
cloud-init configurations for a VM that are set via
the GUI/CLI when a cloud-init disk is attached to it:

* default username, password, and SSH public key
* hostname (via the VM's name) and domain name
* IP configurations
* upgrading packages on boot
* a couple of other general things

Those "automatic" configurations,
while not strictly necessary,
are very useful to Proxmox VMs using cloud-init.

They are part of the reason why I have chosen to use an
unmodified `cloud-init` image for a VM template over
other VM templating and configuration methods,
especially before I have set up other automation tooling for
my Proxmox/virtualization environment.
In particular, managing the lifecycle of
customized "golden" images with all of the shared configuration baked in
sounded like more work than managing
a couple of configuration files with a publicly available image.

See the [Proxmox cloud-init support documentation] for more information.

### Reasoning for pve-vm-cloudinit

There are more cloud-init customizations that can be
taken advantage of by using the `cicustom` option along
with YAML configuration snippets for QEMU/PVE `qm` VMs:

* additional users and groups
* additional trusted CAs
* installing packages
* running commands
* mounting disks
* and more... read the [cloud-init documentation]

`cicustom` works as expected -
I have a need to update the user data -
however, using it does not automatically include the useful
...automatic... configurations.

Thankfully, it seems that the `qm cloudinit dump <vm_id> <config>`
command outputs the automatic configurations,
and so it is possible -
with the magic of `sCr1p+1Ng` -
to quickly append any additional configurations to
the automatic configurations to better suit my needs.
It is further possible to add a form of templating -
similar to VM templating -
for the configurations.

Ideally, one could use a `hookscript` to update the
`cicustom` settings or
fire off some additional events after a clone,
but the former is unable to change the VM options in
`pre-start` due to a QEMU lock state,
and the latter is not an option
(or maybe I haven't found that option;
regarding VM lifecycle hooks:
create, clone, destroy,
~~pre/post-start/stop can use `hookscript`~~,
...).

The set of `pve-vm-cloudinit` scripts are designed to
configure PVE VMs with additional cloud-init configurations along
with the automatic configurations to use in the `cicustom` option.

There are additional commands to help with creating templates from
cloud-init-ready OS disk image files (e.g. `qcow2`).

## Installation

To install the `pve-vm-cloudinit` scripts,
copy the files under the [bin](./bin) directory to a `~/.local/bin` directory.
Make sure that the files are executable and that `~/.local/bin` is on your path.

```sh
# copy the files
mkdir -p ~/.local/bin
wget -P ~/.local/bin https://raw.githubusercontent.com/j1mbl3s/pve-vm-cloudinit/main/bin/pve-vm-cloudinit.sh
chmod +x ~/.local/bin/pve-vm-cloudinit.sh

# ensure ~/.local/bin is on your PATH (via ~/.bashrc)
[[ "$(echo "$PATH" | grep -vE '(^|:)'"$HOME"'/.local/bin(:|$)')" ]] \
    && echo 'export PATH=~/.local/bin:$PATH' >> ~/.bashrc && source ~/.bashrc
```

### Uninstall

Remove the `pve-vm-cloudinit.sh` script that you installed
in the `~/.local/bin` directory.

```sh
rm ~/.local/bin/pve-vm-cloudinit.sh
```

The `~/.local/bin` directory is the standard for user executables.
Do what you want with that.

## Prerequisites

1. Configure Proxmox storage on the node for "Disk image" and "Snippets".
    See `man pvesm` and/or `Datacenter -> Storage` in the GUI.

    * Disk image should be under an LVM-Thin storage type.

        * Any storage type compatible with Disk image _should_ work.
            I don't know if there are any differences in the
            requirements for the commands used in the scripts,
            since this is my PVE storage setup at the moment.
        
            Block-level storage with snapshotting is ideal (hence LVM-Thin).
            Ceph/RBD or ZFS/iSCSI if you need to share block-level storage with
            snapshotting among PVE nodes.

        * Examples use the `data-lvm-thin` storage.

    * Snippets should be under a Directory storage type.

        * Any storage type compatible with Snippets _should_ work,
            i.e. file-level storage.

        * Examples use the `local` storage mounted to `/var/lib/vz`.

2. Download the cloud-init-ready OS image file that you want to run.

###### Example: Download a cloud-init OS image

```sh
mkdir -p ~/qcow
wget -O ~/qcow/debian-12-generic-amd64.qcow2 https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
```

## Usage

```txt
usage: pve-vm-cloudinit.sh [-d] [-q] [-v] <command>

    Manage and customize `cloud-init`-ready Proxmox VMs.
    It is mostly so you do not have to remember all of the commands for customizing the `cloud-init` configurations for a VM, and provides a reference point for making `cloud-init` configuration customizations and templates.

    See `pve-vm-cloudinit.sh help <command>` for additional help and arguments.

    Commands:
        template <arguments>
        clone <arguments>
        reconfig <arguments>
        config <arguments>
        destroy <arguments>
        help <command>
        
    Options (does not affect "help"):
        -d, --dry-run
            Do not make any modifications
        -q, --quiet
            Suppress normal output
        -v, --verbose
            Print additional info
```

### Create a template

```txt
usage: pve-vm-cloudinit.sh template [-d] [-e] [-i] [-s] <template_vm_id> <cloudinit_img> <disk_storage_id> [<qm_create_opts>...]

    Create a `cloud-init`-ready Proxmox VM template with the specified ID from a `cloud-init`-ready OS disk image file using the specified Proxmox storage for the VM's disk images.
    See `man qm` and `man pvesm`.

    A name for the template is automatically generated from the cloudinit_img file name without extensions.
    You can override the name by passing your own `--name <name>` in qm_create_opts.
    In fact, any `qm create` option that this command sets may be overridden by passing in your own.

    You may further customize this template as you would normally.
    Note the disks and boot order that this command generates:

    * scsi0 (<disk_storage_id>:vm-<template_vm_id>-disk-0)
        - the `cloud-init`-ready OS drive
    * ide2 (<disk_storage_id>:vm-<template_vm_id>-cloudinit)
        - the `cloud-init` config drive
    * boot order=scsi0

    You may add additional `cloud-init` configurations to the automatically generated (via GUI/`qm`) configurations for clones by creating snippets.
    See `pve-vm-cloudinit.sh help clone` for more details.

    Arguments:
        template_vm_id
            ID for the new VM template
        cloudinit_img
            File location of a cloud-init-ready OS image
        disk_storage_id
            Storage to use for disks
        snippets_storage_id
            Storage to use for snippets
        qm_create_opts
            Additional options for \`qm create\`
    
    Options:
        -d, --discard
            Set `discard=on` for scsi0
        -e, --efi
            Create efidisk0 as the first disk ("...-disk-0"), for the OCD that needs ordered disk numbers, then scsi0 becomes the second disk ("...-disk-1")
        -i, --iothread
            Set `iothread=1` for scsi0
        -s, --ssd
            Set `ssd=1` for scsi0
```

###### Example: Create a template

```sh
pve-vm-cloudinit.sh template -des \
    9000 ~/qcow/debian-12-generic-amd64.qcow2 data-lvm-thin \
    --cpu x86-64-v2-AES --memory 2048 \
    --scsihw virtio-scsi-single \
    --net0 virtio,bridge=vmbr0,tag=80 \
    --ostype l26 \
    --tags "linux;debian;debian-12;cloudinit;debian-cloudinit;debian-12-cloudinit"
```

Output:

```txt
+ qm create 9000 --name debian-12-generic-amd64 --efidisk0 data-lvm-thin:0 --ide2 data-lvm-thin:cloudinit --scsi0 data-lvm-thin:0,import-from=/root/qcow/debian-12-generic-amd64.qcow2,discard=on,ssd=1 --boot order=scsi0 --cpu x86-64-v2-AES --memory 2048 --scsihw virtio-scsi-single --net0 virtio,bridge=vmbr0,tag=80 --ostype l26 --tags 'linux;debian;debian-12;cloudinit;debian-cloudinit;debian-12-cloudinit'
  Rounding up size to full physical extent 4.00 MiB
  Logical volume "vm-9000-disk-0" created.
transferred 0.0 B of 128.0 KiB (0.00%)
transferred 128.0 KiB of 128.0 KiB (100.00%)
transferred 128.0 KiB of 128.0 KiB (100.00%)
efidisk0: successfully created disk 'data-lvm-thin:vm-9000-disk-0,size=4M'
  Logical volume "vm-9000-cloudinit" created.
ide2: successfully created disk 'data-lvm-thin:vm-9000-cloudinit,media=cdrom'
  Logical volume "vm-9000-disk-1" created.
transferred 0.0 B of 2.0 GiB (0.00%)
[...]
transferred 2.0 GiB of 2.0 GiB (100.00%)
scsi0: successfully created disk 'data-lvm-thin:vm-9000-disk-1,discard=on,size=2G,ssd=1'
```

#### Additional template configurations

Through the Proxmox UI or CLI,
modify any settings for the VM template,
particularly the `Cloud-Init` settings.
These settings will be the "automatic" configs for
cloud-init on the template.
They will be copied into any VM clones.

For `Cloud-Init` "automatic" settings, I like to set specifically:

1. an SSH key (or password) for the default user
    (for Debian, that's `debian`)
2. `ip=dhcp` for IP config
    (after cloning the template, I add a DHCP reservation for the clone's `net0` device)

These settings will be copied to the cloned VM.
In this configuration (without additional hostname/DNS settings),
a VM's FQDN name will be determined by the VM's name.

You may change any other settings for the VM through the CLI,
such as disk resizing
(e.g. to increase the OS disk size - `qm disk resize local:vm-9000-disk-1 8G`),
with one exception.

While using `pve-vm-cloudinit.sh`, do not modify `cicustom`.
The `config` command('s only purpose) is to set `cicustom` to
a setting based on the existence of `vm-<vm_id>-cloudinit-<config>.yaml` snippets.
See [the `clone` example](#example-clone-the-template).

##### Further cloud-init customizations

Create/modify the `vm-<template_vm_id>-cloudinit-<config>-add.yaml`
files which will be appended to the automatic configurations
to generate the `cicustom` files for the cloned VMs.

`<config>` can be any of `user`, `network`, `meta`, `vendor`.

See the [cloud-init documentation] for more details about configuration.

###### Example: Further cloud-init customizations

`/var/lib/vz/snippets/vm-9000-cloudinit-user-add.yaml`:

```yaml
ca_certs:
  trusted:
    - |
      -----BEGIN CERTIFICATE-----
      MIIB/TCCAaOgAwIBAgIUSRtJWIwPdKDyh3HpsBbpQL0DSIwwCgYIKoZIzj0EAwIw
      TDEcMBoGA1UECgwTSmFpbWUgSmFja3Nvbi1CbG9jazEsMCoGA1UEAwwjSmFpbWUg
      SmFja3Nvbi1CbG9jayBQcml2YXRlIFJvb3QgRUMwHhcNMjQwNTEyMTQwNjAyWhcN
      MzQwNTEwMTQwNjAyWjBMMRwwGgYDVQQKDBNKYWltZSBKYWNrc29uLUJsb2NrMSww
      KgYDVQQDDCNKYWltZSBKYWNrc29uLUJsb2NrIFByaXZhdGUgUm9vdCBFQzBZMBMG
      ByqGSM49AgEGCCqGSM49AwEHA0IABBf4eVc18o6cPJz5dFj2vlEBEzvjoablLTHI
      RJgeAup1vdjebHYFwOB1d38GQCtX0CTwGnBb89UxJ7VZY4GlmGCjYzBhMB0GA1Ud
      DgQWBBT0C8NpoZZ/nwkM3ryOWSBbobYMVDAfBgNVHSMEGDAWgBT0C8NpoZZ/nwkM
      3ryOWSBbobYMVDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAKBggq
      hkjOPQQDAgNIADBFAiEAtSRZyNCODBqwT5swzfLdvnz8EgnoqoRoBzrnB4wPyKcC
      IB8+Z9YdlglCFscSzJIjL16e96Am9y4VOiCR/Y7budlQ
      -----END CERTIFICATE-----
packages:
  - htop
  - tmux
  - zsh
```

### Clone the template

```txt
usage: pve-vm-cloudinit.sh clone <template_vm_id> <clone_vm_id> <snippets_storage_id> [<qm_clone_opts>...]

    Clone a `cloud-init`-ready VM template to a new VM.
    See `man qm` and `man pvesm`.

    This also runs the `reconfig` command with the template_vm_id, clone_vm_id, and snippets_storage_id.

    You may further customize this VM and the "vm-<clone_vm_id>-cloudinit-<config>[-add].yaml" snippet files.
    See `pve-vm-cloudinit.sh help reconfig` and `pve-vm-cloudinit.sh help config` for additional configuration snippet-related commands.

    Arguments:
        template_vm_id
            ID of the VM template to clone
        clone_vm_id
            ID for the newly cloned VM
        snippets_storage_id
            Storage to use for snippets
        qm_clone_opts
            Additional options for `qm clone`
```

###### Example: Clone the template

```sh
pve-vm-cloudinit.sh clone 9000 100 local \
    --full --name cloudi1
```

Output:

```txt
+ qm clone 9000 100 --full --name cloudi0.home.jaimejb.net
create full clone of drive efidisk0 (data-lvm-thin:vm-9000-disk-0)
  Rounding up size to full physical extent 4.00 MiB
  Logical volume "vm-100-disk-0" created.
create full clone of drive ide2 (data-lvm-thin:vm-9000-cloudinit)
  Logical volume "vm-100-cloudinit" created.
create full clone of drive scsi0 (data-lvm-thin:vm-9000-disk-1)
  Logical volume "vm-100-disk-1" created.
transferred 0.0 B of 2.0 GiB (0.00%)
[...]
transferred 2.0 GiB of 2.0 GiB (100.00%)
+ cp /var/lib/vz/snippets/vm-9000-cloudinit-user-add.yaml /var/lib/vz/snippets/vm-100-cloudinit-user-add.yaml
+ qm cloudinit dump 100 user
+ cat - /var/lib/vz/snippets/vm-100-cloudinit-user-add.yaml
+ qm set 100 --cicustom user=local:snippets/vm-100-cloudinit-user.yaml
update VM 100: -cicustom user=local:snippets/vm-100-cloudinit-user.yaml
```

#### Additional VM configurations

After a VM is cloned from a template, you can further customize it through the GUI and CLI.

You may further customize the `vm-<clone_vm_id>-cloudinit-<config>.yaml` files if you choose.
Note that these further customizations would be overwritten by the `reconfig` command.

Also note that changes to the automatic cloud-init configurations
(or `vm-<clone_vm_id>-cloudinit-config-add.yaml` files)
will require a run of the `reconfig` command to take effect,
using the `clone_vm_id` as both `<template_vm_id>` and `<clone_vm_id>` arguments.
See the `reconfig` example.

### Reconfigure templated files

```txt
usage: pve-vm-cloudinit.sh reconfig <template_vm_id> <clone_vm_id> <snippets_storage_id>

    Copy any additional `cloud-init` configuration snippets files "vm-<template_vm_id>-cloudinit-<config>-add.yaml" to  "vm-<clone_vm_id>-cloudinit-<config>-add.yaml", where config is "meta", "network", "user", or "vendor".
    When the "vm-<clone_vm_id>-cloudinit-<config>-add.yaml" snippet exists, the file will be appended to the automatically generated configurations for the clone as "vm-<clone_vm_id>-cloudinit-<config>.yaml".

    This also runs the `config` command with the clone and snippets storage.

    Arguments:
        template_vm_id
            ID of the VM to use for additional configurations
        clone_vm_id
            ID of the VM to update configs for
        snippets_storage_id
            Storage to use for snippets
```

###### Example: Reconfigure cloud-init customizations

```sh
pve-vm-cloudinit.sh reconfig 100 100 local
```

Output:

```txt
+ qm cloudinit dump 100 user
+ cat - /var/lib/vz/snippets/vm-100-cloudinit-user-add.yaml
+ qm set 100 --cicustom user=local:snippets/vm-100-cloudinit-user.yaml
update VM 100: -cicustom user=local:snippets/vm-100-cloudinit-user.yaml
```

### Configure snippets for VM

```txt
usage: pve-vm-cloudinit.sh config [-A] <vm_id> <snippets_storage_id>

    Configure "cicustom" for the VM based on the existence of "vm-<vm_id>-cloudinit-<config>.yaml" snippet files, where config is "meta", "network", "user", or "vendor".
    See `man qm`.

    Arguments:
        vm_id
            ID of the VM to update configs for
        snippets_storage_id
            Storage to use for snippets
```

###### Example: Configure snippets for VM

```sh
pve-vm-cloudinit.sh config 100 local
```

Output:

```txt
+ qm set 100 --cicustom user=local:snippets/vm-100-cloudinit-user.yaml
update VM 100: -cicustom user=local:snippets/vm-100-cloudinit-user.yaml
```

### Start and stop the VM

Use the GUI or CLI.
Have fun!

### Destroy the VM or template

```txt
usage: pve-vm-cloudinit.sh destroy <vm_id> <snippets_storage_id>

    Destroy the VM and delete any "vm-<vm_id>-cloudinit-<config>[-add].yaml" snippet files.

    Arguments:
        vm_id
            ID of the VM to destroy
        snippets_storage_id
            Storage to use for snippets
```

###### Example: Destroy the VM or template

```sh
pve-vm-cloudinit.sh destroy 100 local
```

Output:

```txt
+ qm destroy 100
  Logical volume "vm-100-cloudinit" successfully removed.
  Logical volume "vm-100-disk-1" successfully removed.
  Logical volume "vm-100-disk-0" successfully removed.
+ find /var/lib/vz/snippets -regex '/var/lib/vz/snippets/vm-100-cloudinit-\(meta\|network\|user\|vendor\)\(-add\)?\.yaml'
+ xargs rm
```


[# References #]: #
[cloud-init documentation]: https://cloudinit.readthedocs.io/en/latest/
[Proxmox cloud-init support documentation]: https://pve.proxmox.com/wiki/Cloud-Init_Support