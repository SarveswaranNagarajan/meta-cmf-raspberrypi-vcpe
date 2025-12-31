# Remove CAP_SYS_RAWIO and CAP_SYS_MODULE from process-capabilities.json
# These capabilities are not available in LXD container bounding set,
# causing capability setting to fail entirely and leaving processes
# with CapEff=0 (no effective capabilities including CAP_DAC_OVERRIDE)

do_install:append() {
    # Remove CAP_SYS_RAWIO and CAP_SYS_MODULE from all entries
    sed -i 's/,CAP_SYS_RAWIO//g; s/CAP_SYS_RAWIO,//g; s/CAP_SYS_RAWIO//g' \
        ${D}${sysconfdir}/security/caps/process-capabilities.json
    sed -i 's/,CAP_SYS_MODULE//g; s/CAP_SYS_MODULE,//g; s/CAP_SYS_MODULE//g' \
        ${D}${sysconfdir}/security/caps/process-capabilities.json
}
