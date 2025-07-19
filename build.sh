#!/bin/bash
set -e
TC_DIR="toolchain"

GCC_TC_BRANCH="pie-gsi"
GCC_TC_URL="https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9"
GCC_TC_DIR="gcc-${GCC_TC_BRANCH}"

CLANG_TC_BRANCH="android11-gsi"
CLANG_TC_REV="clang-r383902"
CLANG_TC_URL="https://android.googlesource.com/platform//prebuilts/clang/host/linux-x86"
CLANG_CLONE_DIR="clang-${CLANG_TC_BRANCH}"
CLANG_TC_DIR="${CLANG_TC_REV}"

if [ ! -e "${TC_DIR}" ]; then
	echo "Downloading toolchain"
	
	if ! command -v "git" &>/dev/null; then
		echo "Could not find git"
		exit 1
	fi
	mkdir -p "${TC_DIR}"

	pushd "${TC_DIR}" &>/dev/null
		git clone --depth 1 -b "${GCC_TC_BRANCH}" "${GCC_TC_URL}" "${GCC_TC_DIR}"
		
		# Clone clang
		git clone --no-checkout --sparse --filter=tree:0 --depth=1 --single-branch -b "${CLANG_TC_BRANCH}" "${CLANG_TC_URL}" "${CLANG_CLONE_DIR}"
		git -C "${CLANG_CLONE_DIR}" sparse-checkout set --no-cone "/${CLANG_TC_REV}"
		git -C "${CLANG_CLONE_DIR}" checkout --progress --force

		mv "${CLANG_CLONE_DIR}/${CLANG_TC_REV}" "${CLANG_TC_DIR}"
		rm -rf "${CLANG_CLONE_DIR}"
	popd &>/dev/null
fi

#export ROOTDIR=$PWD
export PATH="$PWD/${TC_DIR}/${CLANG_TC_DIR}/bin:${PATH}"
export PATH="$PWD/${TC_DIR}/${GCC_TC_DIR}/bin:${PATH}"

BUILD_ARGS=(
	"O=out"
	"ARCH=arm64"
	"CROSS_COMPILE=aarch64-linux-androidkernel-"
	
	"CC=clang"
	"NM=llvm-nm"
	"OBJCOPY=llvm-objcopy"
	"CLANG_TRIPLE=aarch64-linux-gnu-"
	
	"LD=ld.lld"
	"LD_LIBRARY_PATH=$PWD/${TC_DIR}/${CLANG_TC_DIR}/lib64:"
)

echo "Path: ${PATH}"
echo "Build args: ${BUILD_ARGS[@]}"

if [ ! -e "arch/arm64/configs/droidian" ]; then
	echo "Downloading common fragments"
	git clone --depth 1 -b "4.19-android" "https://github.com/droidian-devices/common_fragments/" "arch/arm64/configs/droidian"
fi

make "${BUILD_ARGS[@]}" P98928AA1_defconfig droidian/halium.config droidian/droidian.config droidian-extra.config
make "${BUILD_ARGS[@]}" -j4

mkdir -p out/modules
make "${BUILD_ARGS[@]}" INSTALL_MOD_PATH=modules modules_install 

echo "Creating boot image"
mkbootimg --header_version 2 --os_version 11.0.0 --os_patch_level 2022-03 --kernel out/arch/arm64/boot/Image.gz --ramdisk custom/ramdisk --dtb custom/devicetree --pagesize 0x00000800 --base 0x00000000 --kernel_offset 0x40080000 --ramdisk_offset 0x51b00000 --second_offset 0x00000000 --tags_offset 0x47880000 --dtb_offset 0x0000000047880000 --board '' --cmdline 'bootopt=64S3,32N2,64N2 buildvariant=user systempart=/dev/disk/by-partlabel/userdata' -o out/boot.img