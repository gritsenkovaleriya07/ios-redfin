#!/bin/bash
# Pack kernel + ADT + boot-args into a shim boot image and fastboot-boot it
# on the Pixel 4a 5G (bramble). RAM only: nothing is flashed.
#
#   tools/bramble-boot.sh NAME KERNEL [EXTRA BOOT-ARGS...]
#
# tools/redfin-boot.sh for bramble. The differences:
#   - touch is ST FTS on SPI SE0 (xnu 1201): flametouch=1, sectouch=0. sectouch=1 is refused: the redfin
#     sec_ts driver would talk the Samsung protocol to the FTS chip (and votes L17A at 3304 mV, which 1201's
#     allow-list now refuses: bramble's L17A is a 1.8 V camera-sensor rail).
#   - no camera/torch/haptics preset yet: bramble's cameras differ from redfin's.
#   - GPUFW must be given (the folder pull-firmware.sh fills, e.g. fw-bramble/).
#
# Environment:
#   GPU=0|1|2      CPU rendering / kernel GPU present / plus Metal on Turnip
#   GPUFW=DIR      GPU firmware folder (a650_sqe.fw, a650_gmu.bin, a620_zap.*), required
#   ADT=FILE       the ADT (default work/boot/bramble-hi.adt, made by tools/mkadt.py)
#   NOBOOT=1       build work/boot/NAME.img only (no fastboot)
set -euo pipefail
cd "$(dirname "$0")/.."
name=$1 kernel=$2; shift 2
P=$PWD/work/boot
mkdir -p "$P"
: "${GPUFW:?set GPUFW to the GPU firmware folder (devices/bramble/pull-firmware.sh output)}"
ADT=${ADT:-$P/bramble-hi.adt}
base="debug=0xc serial=3 cpus=8 keepsyms=1 -enable_kprintf_spam -noprogress rd=ufsroot0 ufsrw=1 rootrw=1"
base="$base unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin launchd_unsecure_cache=1"
base="$base wdt=-1 sweetfb_noconsole=1 sweetfb_hz=60 ufslogsecs=2 flamereboot=1800"
base="$base flametouch=1 flametouchdelay=20 sweettouch=0 sweetkeys=1 sweetusb=2 sweetgpu=0 sweetgpufreq=3 sweetgpudelay=0 sweetfb_thread=0 sweetmtl=0 sweetddr=0"
base="$base sweetbattery=1 sectouch=0"
for a in "$@"; do
	case $a in
	sectouch=0) ;;
	sectouch=*) echo "bramble-boot.sh: $a refused (bramble touch is ST FTS: flametouch)" >&2; exit 1 ;;
	esac
done
GPU=${GPU:-0}
if [ "$GPU" -ge 1 ]; then
	base=$(printf '%s\n' $base | grep -v -e '^sweetgpu=' -e '^sweetfb_thread=' -e '^sweetddr=' | tr '\n' ' ')
	base="$base sweetgpu=1 sweetfb_thread=1 sweetddr=1"
fi
if [ "$GPU" -ge 2 ]; then
	base=$(printf '%s\n' $base | grep -v -e '^sweetmtl=' | tr '\n' ' ')
	base="$base sweetmtl=2"
fi
[ -f work/rtc-offset ] && base="$base sweetrtcoff=$(cat work/rtc-offset)"
# Extra args replace defaults with the same key (XNU would take the first).
for a in "$@"; do
	k=${a%%=*}
	base=$(printf '%s\n' $base | grep -v -x -e "$k" -e "$k=.*" | tr '\n' ' ')
done
cmdline="$base $*"
echo "$cmdline" > "$P/$name.cmdline"
python3 -I tools/mkpayload.py "$kernel" "$ADT" "$P/$name.payload" --cmdline "$cmdline" --gpufw "$GPUFW" >/dev/null
shim/build.sh "$P/$name.payload" "$P/$name.img" >/dev/null
if [ "${NOBOOT:-0}" = 1 ]; then
	echo "$(date +%T) built $P/$name.img: $cmdline"
	exit 0
fi
echo "$(date +%T) built $name.img; waiting for fastboot"
until fastboot devices | grep -q fastboot; do sleep 2; done
fastboot boot "$P/$name.img"
echo "$(date +%T) booted $name: $cmdline"
