#!/usr/bin/env bash
#
# Runs the engine on a virtual display inside the capture image. The arguments
# are the launcher's, untouched: this script adds a display and a software
# renderer and nothing else, so a container capture is the same command line as
# a desktop one.
set -u

# Mesa is the only renderer in the image; naming its software devices keeps a
# host driver that leaked in from ever being picked instead. Which one draws is
# the project's rendering method, not this script's business.
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.aarch64.json}"
# The engine writes its editor/user data under $HOME; the checkout is mounted
# read-write but nothing else is, so keep that traffic in the container.
export HOME="${HOME:-/tmp}"

# A headless run draws nothing and must not be wrapped: under xvfb-run the
# import produces no output and never returns.
for arg in "$@"; do
	[[ "$arg" == "--headless" ]] && exec godot "$@"
done

# -a takes the first free display number, so two captures can run at once.
exec xvfb-run -a -s "-screen 0 1920x1080x24" godot "$@"
