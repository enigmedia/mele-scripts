#!/bin/bash

#*****************************************************************************
# Build script for A10 hardware pack
# a10-hwpack-bld.sh product_name
#
# Initial script by cnxsoft at github
# Adapted for Ubuntu 12.04 armel by hackandfab at gmail for Enigmedia S.L
#
#******************************************************************************
blddate=`date +%Y.%m.%d`
cross_compiler=arm-linux-gnueabi-
#********************************************************************************
# Change above from gnueabi to gnueabihf in order to use armhf instead of armel
# armel and armhf are not compatible and there are issues with video and graphic 
# libraries. If you're going to try to understand/reverse cedar libraries use armel.
# armhf is faster.
#
# When I wrote this Ubuntu's arm toolchain was broken and cnxsoft used linaro
# Now it works.
#
# sudo apt-get install gcc-4.4-arm-linux-gnueabi
#
# NOTE: On Debian arm-linux-gnueabi- would be arm-none-linux-gnueabi-
#
#********************************************************************************
board=$1

#******************************************************************************
#
# try: Execute a command with error checking.  Note that when using this, if a piped
# command is used, the '|' must be escaped with '\' when calling try (i.e.
# "try ls \| less").
#
#******************************************************************************
try ()
{
    #
    # Execute the command and fail if it does not return zero.
    #
    eval ${*} || failure
}

#******************************************************************************
#
# failure: Bail out because of an error.
#
#******************************************************************************
failure ()
{
    #
    # Indicate that an error occurred.
    #
    echo Build step failed!

    #
    # Exit with a failure return code.
    #
    exit 1
}

if [ -z $1 ]; then
    echo "Usage: ./a10-hwpack-bld.sh product_name"
    echo ""
    echo "Products currently supported: mele-a1000 and mele-a1000-vga"
    echo ""
    echo "mele-A1000 and mele-A2000 use the same electronics"
    echo "for MK802 remember to change kernel .config for SATA"
    exit 1
fi

try mkdir -p bld_a10_hwpack_${blddate}

try pushd bld_a10_hwpack_${blddate}

make_log=`pwd`/${board}_${blddate}.log
echo "Build hwpack for ${board} - ${blddate}" > ${make_log}

num_core=`grep 'processor' /proc/cpuinfo | sort -u | wc -l`
num_jobs=`expr ${num_core} \* 3 / 2`
if [ ${num_jobs} -le 2 ]; then
    num_jobs=2
fi

echo Number of detected cores = ${num_proc} > ${make_log}
echo Number of jobs = ${num_jobs} > ${make_log}

try mkdir -p ${board}_hwpack/bootloader
try mkdir -p ${board}_hwpack/kernel
try mkdir -p ${board}_hwpack/rootfs

# Generate script.bin
if [ ! -f .script.${board} ]
then
    echo "Checking out config files"
    if [ ! -d a10-config ]; then
        try git clone git://github.com/cnxsoft/a10-config.git >> ${make_log}
    fi
    try pushd a10-config/script.fex >> ${make_log} 2>&1
    echo "Generating ${board}.bin file"
# a esto le faltaba un git clone https://github.com/amery/sunxi-tools
# luego vas dentro y haces un make la primera vez.

    try ../../../sunxi-tools/fex2bin ${board}.fex > ${board}.bin
    popd >> ${make_log} 2>&1
    touch .script.${board}ls

fi

if [ ! -f .uboot-allwinner ]
then
    # Build u-boot
    echo "Checking out u-boot source code"
    #if [ ! -d uboot-allwinner ]; then
    #    try git clone https://github.com/hno/uboot-allwinner.git --depth=1 >> ${make_log}
    #fi
    try pushd uboot-allwinner >> ${make_log} 2>&1
    is_server=`echo $1 | grep "-server"`
    if [ -z $is_server ]; then
        echo "Temporarly patch for v2011.09-sun4i"
        echo "Disable once https://github.com/hno/uboot-allwinner/issues/10 is fixed"
	echo "with mods for FB and to avoid upstart/init pty error without initramfs!"
        try patch -p1 < ../a10-config/patch/u-boot-rootwait-fbmem.patch
    else
        echo "Server build"
        try patch -p1 < ../a10-config/patch/u-boot-rootwait-server.patch
    fi
    echo "Building u-boot"
    try make sun4i CROSS_COMPILE=${cross_compiler} -j ${num_jobs} >> ${make_log} 2>&1
    popd >> ${make_log} 2>&1
    touch .uboot-allwinner
fi

# Build the linux kernel
# Last kernel I used was 3.0.38 and X,eth0,wifi,sata worked. (no FB console, no cedar, no accelerated mali)

if [ ! -f .linux-allwinner ]
then
    echo "Checking out linux source code `pwd`"
    if [ ! -d linux-allwinner ]; then
        try git clone git://github.com/amery/linux-allwinner.git --depth=1 >> ${make_log}
    fi
    try pushd linux-allwinner >> ${make_log} 2>&1
    try git checkout allwinner-v3.0-android-v2 >> ${make_log} 2>&1
    echo "Building linux"
    # cnxsoft: do we need a separate config per device ?
    if [ -f ../a10-config/kernel/${board}.config ]; then
       echo "Use custom kernel configuration"
       echo voy a copiar el /a10-config/kernel/${board}.config al
       echo  `pwd`
       echo va:
       try cp ../a10-config/kernel/${board}.config .config >> ${make_log} 2>&1
       try make ARCH=arm oldconfig >> ${make_log} 2>&1
    else
       echo "Use default kernel configuration"
       try make ARCH=arm sun4i_defconfig >> ${make_log} 2>&1
    fi
    try make ARCH=arm CROSS_COMPILE=${cross_compiler} -j ${num_jobs} uImage >> ${make_log} 2>&1
    echo "Building the kernel modules"
   
    try make ARCH=arm CROSS_COMPILE=${cross_compiler} -j ${num_jobs} INSTALL_MOD_PATH=output modules >> ${make_log} 2>&1
    try make ARCH=arm CROSS_COMPILE=${cross_compiler} -j ${num_jobs} INSTALL_MOD_PATH=output modules_install >> ${make_log} 2>&1
    popd >> ${make_log} 2>&1
    touch .linux-allwinner
fi

# Get binary files
echo "Checking out binary files"
if [ ! -d a10-bin ]; then
    try git clone git://github.com/cnxsoft/a10-bin.git >> ${make_log} 2>&1
fi

# Copy files in hwpack directory
echo "Copy files to hardware pack directory"

# Only support Debian/Ubuntu for now
try cp a10-config/rootfs/debian-ubuntu/* ${board}_hwpack/rootfs -rf >> ${make_log} 2>&1
try cp -r linux-allwinner/output/lib/modules ${board}_hwpack/rootfs

try mkdir -p ${board}_hwpack/rootfs/a10-bin-backup >> ${make_log} 2>&1

# CHANGE THIS TO armhf to use armhf
try cp -r a10-bin/armel/lib/* ${board}_hwpack/rootfs/lib/arm-linux-gnueabi/ -rf >> ${make_log} 2>&1
# http://lwn.net/Articles/482952/
echo "you should edit xorg.conf to use mali (you have the libs for armel)"
echo http://rhombus-tech.net/allwinner_a10/Compile_X11_driver_for_A10/
echo http://comments.gmane.org/gmane.comp.hardware.netbook.arm/3396

try cp linux-allwinner/arch/arm/boot/uImage ${board}_hwpack/kernel >> ${make_log} 2>&1
try cp a10-config/script.fex/${board}.bin ${board}_hwpack/kernel >> ${make_log} 2>&1
try cp uboot-allwinner/spl/sun4i-spl.bin ${board}_hwpack/bootloader >> ${make_log} 2>&1
try cp uboot-allwinner/u-boot.bin ${board}_hwpack/bootloader >> ${make_log} 2>&1


# Compress the hwpack files
echo "Compress hardware pack file"
try pushd ${board}_hwpack >> ${make_log} 2>&1
try 7z a -t7z -m0=lzma -mx=9 -mfb=64 -md=32m -ms=on ../${board}_hwpack_${blddate}.7z . >> ${make_log} 2>&1
popd >> ${make_log} 2>&1
popd >> ${make_log} 2>&1
echo "Build completed - ${board} hardware pack: ${board}_hwpack_${blddate}.7z" >> ${make_log} 2>&1
echo "Build completed - ${board} hardware pack: ${board}_hwpack_${blddate}.7z"

