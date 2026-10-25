# WSL: render through the Windows GPU instead of the llvmpipe software fallback.
# The d3d12 drivers come from the WSL profile package list (mesa, vulkan-dzn):
# https://wiki.archlinux.org/title/Install_Arch_Linux_on_WSL#Hardware_accelerated_rendering
if set -q WSL_DISTRO_NAME
    if not set -q GALLIUM_DRIVER
        set -gx GALLIUM_DRIVER d3d12
    end

    if not set -q LIBVA_DRIVER_NAME
        set -gx LIBVA_DRIVER_NAME d3d12
    end
end
