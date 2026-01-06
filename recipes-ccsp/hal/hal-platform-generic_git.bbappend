do_configure_append(){
    PATCH_DIR="${TOPDIR}/../meta-cmf-raspberrypi-vcpe/recipes-ccsp/hal/${PN}"
    cd ${S}/devices_rpi
    patch -N -p1 < "${PATCH_DIR}/0001-platform_hal-Read-device-info-from-LXC-container-env.patch" || true
    patch -N -p1 < "${PATCH_DIR}/0002-platform_hal-Fix-DHCPv6-Option17-vendor-suboption-en.patch" || true
}
