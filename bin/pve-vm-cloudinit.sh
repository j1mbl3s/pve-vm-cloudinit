#!/bin/bash

printUsage() {
    echo "\
usage: $(basename $0)" \
'[-d] [-q] [-v] <command>

    Manage and customize `cloud-init`-ready Proxmox VMs.
    It is mostly so you do not have to remember all of the commands' \
'for customizing the `cloud-init` configurations for a VM,' \
'and provides a reference point for making `cloud-init` configuration' \
'customizations and templates.

    See' "\`$(basename $0)" 'help <command>` for additional help and arguments.

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
            Print additional info'
}

printTemplateUsage() {
    echo "\
usage: $(basename $0) template" \
'[-d] [-e] [-i] [-s] <template_vm_id> <cloudinit_img> <disk_storage_id> [<qm_create_opts>...]

    Create a `cloud-init`-ready Proxmox VM template with the specified ID from' \
'a `cloud-init`-ready OS disk image file using the specified Proxmox storage for' \
'the' "VM's" 'disk images.
    See `man qm` and `man pvesm`.

    A name for the template is automatically generated from the cloudinit_img' \
'file name without extensions.
    You can override the name by passing your own `--name <name>` in qm_create_opts.
    In fact, any `qm create` option that this command sets may be overridden' \
'by passing in your own.

    You may further customize this template as you would normally.
    Note the' \
'disks and boot order that this command generates:

    * scsi0 (<disk_storage_id>:vm-<template_vm_id>-disk-0)
        - the `cloud-init`-ready OS drive
    * ide2 (<disk_storage_id>:vm-<template_vm_id>-cloudinit)
        - the `cloud-init` config drive
    * boot order=scsi0

    You may add additional `cloud-init` configurations to the automatically' \
'generated (via GUI/`qm`) configurations for clones by creating snippets.
    See' "\`$(basename $0)" 'help clone` for more details.

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
            Create efidisk0 as the first disk ("...-disk-0"),' \
'for the OCD that needs ordered disk numbers,' \
'then scsi0 becomes the second disk ("...-disk-1")
        -i, --iothread
            Set `iothread=1` for scsi0
        -s, --ssd
            Set `ssd=1` for scsi0'
}

printCloneUsage() {
    echo "\
usage: $(basename $0) clone" \
'<template_vm_id> <clone_vm_id> <snippets_storage_id> [<qm_clone_opts>...]

    Clone a `cloud-init`-ready VM template to a new VM.
    See `man qm` and `man pvesm`.

    This also runs the `reconfig` command with the template_vm_id, clone_vm_id,' \
'and snippets_storage_id.

    You may further customize this VM and the' \
'"vm-<clone_vm_id>-cloudinit-<config>[-add].yaml" snippet files.
    See' "\`$(basename $0)" 'help reconfig` and' "\`$(basename $0)" 'help config`' \
'for additional configuration snippet-related commands.

    Arguments:
        template_vm_id
            ID of the VM template to clone
        clone_vm_id
            ID for the newly cloned VM
        snippets_storage_id
            Storage to use for snippets
        qm_clone_opts
            Additional options for `qm clone`'
}

printReconfigUsage() {
    echo "\
usage: $(basename $0) reconfig" \
'<template_vm_id> <clone_vm_id> <snippets_storage_id>

    Copy any additional `cloud-init` configuration snippets files' \
'"vm-<template_vm_id>-cloudinit-<config>-add.yaml" to ' \
'"vm-<clone_vm_id>-cloudinit-<config>-add.yaml",' \
'where config is "meta", "network", "user", or "vendor".
    When the "vm-<clone_vm_id>-cloudinit-<config>-add.yaml" snippet exists,' \
'the file will be appended to the automatically generated configurations for' \
'the clone as' \
'"vm-<clone_vm_id>-cloudinit-<config>.yaml".

    This also runs the `config` command with the clone and snippets storage.

    Arguments:
        template_vm_id
            ID of the VM to use for additional configurations
        clone_vm_id
            ID of the VM to update configs for
        snippets_storage_id
            Storage to use for snippets'
}

printConfigUsage() {
    echo "\
usage: $(basename $0) config" \
'[-A] <vm_id> <snippets_storage_id>

    Configure "cicustom" for the VM based on the existence of' \
'"vm-<vm_id>-cloudinit-<config>.yaml" snippet files,' \
'where config is "meta", "network", "user", or "vendor".
    See `man qm`.

    Arguments:
        vm_id
            ID of the VM to update configs for
        snippets_storage_id
            Storage to use for snippets'
}

printDestroyUsage() {
    echo "\
usage: $(basename $0) destroy" \
'<vm_id> <snippets_storage_id>

    Destroy the VM and delete any' \
'"vm-<vm_id>-cloudinit-<config>[-add].yaml" snippet files.

    Arguments:
        vm_id
            ID of the VM to destroy
        snippets_storage_id
            Storage to use for snippets'
}

runCommand() {
    case $1 in
        template ) template "${@:2}" ;;
        clone ) clone "${@:2}" ;;
        reconfig ) reconfig "${@:2}" ;;
        config ) config "${@:2}" ;;
        destroy ) destroy "${@:2}" ;;
        help | "" )
            case $2 in
                template ) printTemplateUsage ;;
                clone ) printCloneUsage ;;
                reconfig ) printReconfigUsage ;;
                config ) printConfigUsage ;;
                destroy ) printDestroyUsage ;;
                help | "" ) printUsage ;;
                * )
                    echo "unknown help command \"$2\""
                    printUsage
                    exit 1 ;;
            esac ;;
        * )
            echo "unknown command \"$1\""
            printUsage
            exit 1 ;;
    esac
}

runInternal() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo -n "$2" | xargs -d $'\x1F' bash -c 'echo "runInternal:" "'"$1"'"' --
    fi

    if [[ $DRY_RUN -eq 0 ]]; then
        if [[ $QUIET -eq 0 ]]; then
            echo -n "$2" | xargs -d $'\x1F' bash -xc "$1" --
        else
            echo -n "$2" | xargs -d $'\x1F' bash -c "$1" --
        fi
    fi
    
    EXIT=$?
    if [[ $EXIT -ne 0 ]]; then
        echo "detected exit code ""$EXIT"", exiting"
        exit 1
    fi
}

template() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo "template: entering"
    fi

    DISCARD=0
    EFI=0
    IOTHREAD=0
    SSD=0
    while true; do
        case "$1" in
            --* )
                case "$1" in
                    --discard ) DISCARD=1 ;;
                    --efi ) EFI=1 ;;
                    --iothread ) IOTHREAD=1 ;;
                    --ssd ) SSD=1 ;;
                    * )
                        echo "unknown option \"$1\""
                        printTemplateUsage
                        exit 1 ;;
                esac
                shift ;;
            -* )
                for ((I = 1; I < ${#1}; I++)); do
                    case "${1:I:1}" in
                        d ) DISCARD=1 ;;
                        e ) EFI=1 ;;
                        i ) IOTHREAD=1 ;;
                        s ) SSD=1 ;;
                        * )
                            echo "unknown option \"-${1:I:1}\""
                            printTemplateUsage
                            exit 1 ;;
                    esac
                done
                shift ;;
            * ) break ;;
        esac
    done

    if [[ $# -lt 3 ]]; then
        echo "incorrect number of arguments"
        printTemplateUsage
        exit 1
    fi
    TEMPLATE_VM_ID="$1"
    CLOUDINIT_IMG="$2"
    DISK_STORAGE_ID="$3"

    runInternal \
        'qm create "$@"' \
        "$(
            echo -n "$TEMPLATE_VM_ID"$'\x1F'
            echo -n "--template"$'\x1F'
            echo -n "--name"$'\x1F'"$(basename "$CLOUDINIT_IMG" | cut -d . -f 1)"$'\x1F'
            if [[ $EFI -eq 1 ]]; then
                echo -n "--efidisk0"$'\x1F'"${DISK_STORAGE_ID}:0"$'\x1F'
            fi
            echo -n "--ide2"$'\x1F'"${DISK_STORAGE_ID}:cloudinit"$'\x1F'
            echo -n "--scsi0"$'\x1F'"${DISK_STORAGE_ID}:0,import-from=${CLOUDINIT_IMG}$(
                    [[ $DISCARD -eq 1 ]] && echo -n ",discard=on")$(
                    [[ $IOTHREAD -eq 1 ]] && echo -n ",iothread=1")$(
                    [[ $SSD -eq 1 ]] && echo -n ",ssd=1")"$'\x1F'
            echo -n "--boot"$'\x1F'"order=scsi0"
            for ((I = 4; I <= $#; I++)); do
                echo -n $'\x1F'"${@:I:1}"
            done
        )"

    if [[ $VERBOSE -eq 1 ]]; then
        echo "template: exiting"
    fi
}

clone() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo "clone: entering"
    fi

    if [[ $# -lt 3 ]]; then
        echo "incorrect number of arguments"
        printCloneUsage
        exit 1
    fi
    TEMPLATE_VM_ID="$1"
    CLONE_VM_ID="$2"
    SNIPPETS_STORAGE_ID="$3"
    
    runInternal \
        'qm clone "$@"' \
        "$(
            echo -n "$TEMPLATE_VM_ID"$'\x1F'"$CLONE_VM_ID"
            for ((I = 4; I <= $#; I++)); do
                echo -n $'\x1F'"${@:I:1}"
            done
        )"

    reconfig "$TEMPLATE_VM_ID" "$CLONE_VM_ID" "$SNIPPETS_STORAGE_ID"

    if [[ $VERBOSE -eq 1 ]]; then
        echo "clone: exiting"
    fi
}

reconfig() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo "reconfig: entering"
    fi

    if [[ $# -ne 3 ]]; then
        echo "incorrect number of arguments"
        printReconfigUsage
        exit 1
    fi
    TEMPLATE_VM_ID="$1"
    CLONE_VM_ID="$2"
    SNIPPETS_STORAGE_ID="$3"

    SNIPPETS_DIR="$(dirname "$(pvesm path "${SNIPPETS_STORAGE_ID}:snippets/.")")"
    TEMPLATE_SNIPPETS_BASE="vm-${TEMPLATE_VM_ID}-cloudinit"
    CLONE_SNIPPETS_BASE="vm-${CLONE_VM_ID}-cloudinit"
    
    for CONFIG in meta network user vendor; do
        TEMPLATE_SNIPPETS_CONFIG_ADD="${TEMPLATE_SNIPPETS_BASE}-${CONFIG}-add.yaml"
        TEMPLATE_SNIPPETS_CONFIG_ADD_FILE="${SNIPPETS_DIR}/${TEMPLATE_SNIPPETS_CONFIG_ADD}"
        CLONE_SNIPPETS_CONFIG_ADD="${CLONE_SNIPPETS_BASE}-${CONFIG}-add.yaml"
        CLONE_SNIPPETS_CONFIG_ADD_FILE="${SNIPPETS_DIR}/${CLONE_SNIPPETS_CONFIG_ADD}"

        if [[
            "$TEMPLATE_VM_ID" != "$CLONE_VM_ID" \
            && -f "$TEMPLATE_SNIPPETS_CONFIG_ADD_FILE" \
        ]]; then
            runInternal \
                'cp "$@"' \
                "$TEMPLATE_SNIPPETS_CONFIG_ADD_FILE"$'\x1F'"$CLONE_SNIPPETS_CONFIG_ADD_FILE"
        fi

        if [[ -f "$CLONE_SNIPPETS_CONFIG_ADD_FILE" ]]; then
            CLONE_SNIPPETS_CONFIG="${SNIPPETS_DIR}/${CLONE_SNIPPETS_BASE}-${CONFIG}.yaml"
            runInternal \
                'qm cloudinit dump "$@" | cat - "'"$CLONE_SNIPPETS_CONFIG_ADD_FILE"'" >"'"$CLONE_SNIPPETS_CONFIG"'"' \
                "$CLONE_VM_ID"$'\x1F'"$CONFIG"
        fi
    done

    config "$CLONE_VM_ID" "$SNIPPETS_STORAGE_ID"

    if [[ $VERBOSE -eq 1 ]]; then
        echo "reconfig: exiting"
    fi
}

config() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo "config: entering"
    fi

    if [[ $# -ne 2 ]]; then
        echo "incorrect number of arguments"
        printConfigUsage
        exit 1
    fi
    VM_ID="$1"
    SNIPPETS_STORAGE_ID="$2"

    SNIPPETS_DIR="$(dirname "$(pvesm path "${SNIPPETS_STORAGE_ID}:snippets/.")")"
    SNIPPETS_BASE="vm-${VM_ID}-cloudinit"

    CICUSTOM=""
    for CONFIG in meta network user vendor; do
        SNIPPETS_CONFIG="${SNIPPETS_BASE}-${CONFIG}.yaml"

        if [[ -f "${SNIPPETS_DIR}/${SNIPPETS_CONFIG}" ]]; then
            if [[ "$CICUSTOM" ]]; then
                CICUSTOM="${CICUSTOM},"
            fi
            CICUSTOM="${CICUSTOM}${CONFIG}=${SNIPPETS_STORAGE_ID}:snippets/${SNIPPETS_CONFIG}"
        fi
    done

    runInternal \
        'qm set "$@"' \
        "$(
            echo -n "$VM_ID"$'\x1F'
            if [[ "$CICUSTOM" ]]; then
                echo -n "--cicustom"$'\x1F'"$CICUSTOM"
            else
                echo -n "--delete"$'\x1F'"cicustom"
            fi
        )"

    if [[ $VERBOSE -eq 1 ]]; then
        echo "config: exiting"
    fi
}

destroy() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo "destroy: entering"
    fi

    if [[ $# -lt 2 ]]; then
        echo "not enough arguments"
        printDestroyUsage
        exit 1
    fi
    VM_ID="$1"
    SNIPPETS_STORAGE_ID="$2"

    SNIPPETS_DIR="$(dirname "$(pvesm path "${SNIPPETS_STORAGE_ID}:snippets/.")")"
    SNIPPETS_BASE="vm-${VM_ID}-cloudinit"
    SNIPPETS_BASE_FILE="${SNIPPETS_DIR}/${SNIPPETS_BASE}"

    runInternal \
        'qm destroy "$@"' \
        "$VM_ID"

    runInternal \
        'find "$1" -regex "$2" | xargs rm' \
        "$SNIPPETS_DIR"$'\x1F'"${SNIPPETS_BASE_FILE}-\(meta\|network\|user\|vendor\)\(-add\)?\.yaml"
    
    if [[ $VERBOSE -eq 1 ]]; then
        echo "destroy: exiting"
    fi
}

DRY_RUN=0
QUIET=0
VERBOSE=0
while true; do
    case "$1" in
        --* )
            case "$1" in
                --dry-run ) DRY_RUN=1 ;;
                --quiet ) QUIET=1 ;;
                --verbose ) VERBOSE=1 ;;
                * )
                    echo "unknown option \"$1\""
                    printUsage
                    exit 1 ;;
            esac
            shift ;;
        -* )
            for ((I = 1; I < ${#1}; I++)); do
                case "${1:I:1}" in
                    d ) DRY_RUN=1 ;;
                    q ) QUIET=1 ;;
                    v ) VERBOSE=1 ;;
                    * )
                        echo "unknown option \"-${1:I:1}\""
                        printUsage
                        exit 1 ;;
                esac
            done
            shift ;;
        * ) break ;;
    esac
done
runCommand "$@"
