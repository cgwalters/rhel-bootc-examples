#!/usr/bin/bash
# Dracut module for composefs root setup.
# Installs the composefs-setup-root binary and service into the initramfs.

check() {
    return 0
}

depends() {
    return 0
}

install() {
    inst \
        "${moddir}/composefs-setup-root" /bin/composefs-setup-root
    inst \
        "${moddir}/composefs-setup-root.service" \
        "${systemdsystemunitdir}/composefs-setup-root.service"

    $SYSTEMCTL -q --root "${initdir}" add-wants \
        'initrd-root-fs.target' 'composefs-setup-root.service'
}
