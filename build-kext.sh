#!/bin/zsh
# Build the AppleALC kext binary (x86_64, Release-like) with Command Line Tools only.
# Needs: MacKernelSDK/, Lilu.kext (SDK), AppleALC/kern_resources.cpp (ResourceConverter/generate.sh).
# Output: build/AppleALC (Mach-O kext executable). Info.plist is taken from an existing AppleALC.kext.
set -euo pipefail
cd "${0:A:h}"
OUT=build/obj
mkdir -p $OUT
VER=$(sed -n 's/.*MODULE_VERSION = \([0-9.]*\);/\1/p' AppleALC.xcodeproj/project.pbxproj | head -1)

CXXFLAGS=(
	-arch x86_64 -mkernel -fapple-kext -nostdinc -nostdlib
	-std=gnu++14 -O3 -fno-rtti -fno-exceptions -fno-builtin -fno-common
	-mmmx -msse -msse2 -msse3 -mfpmath=sse -mssse3 -ftree-vectorize
	-fno-non-call-exceptions -fno-asynchronous-unwind-tables
	-mmacosx-version-min=10.13
	-Wno-unknown-warning-option -Wno-ossharedptr-misuse -Wno-vla -Wno-stdlibcxx-not-found -Wno-deprecated-declarations
	-DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT
	-DMODULE_VERSION=$VER -DPRODUCT_NAME=AppleALC -DHAVE_ANALOG_AUDIO=1
	-I MacKernelSDK/Headers -I Lilu.kext/Contents/Resources -I AppleALC -I AppleALC/ALCUserClient -I AppleALC/ALCUserClientProvider
)

srcs=(
	AppleALC/kern_alc.cpp
	AppleALC/kern_start.cpp
	AppleALC/kern_resources.cpp
	AppleALC/ALCUserClient/ALCUserClient.cpp
	AppleALC/ALCUserClientProvider/ALCUserClientProvider.cpp
	Lilu.kext/Contents/Resources/Library/plugin_start.cpp
)

objs=()
for s in $srcs; do
	o=$OUT/${${s:t}%.cpp}.o
	echo "CXX $s"
	clang++ $CXXFLAGS -c $s -o $o
	objs+=$o
done

# kmod_info, as Xcode generates it for a kext target
cat > $OUT/info.c <<EOF
#include <mach/mach_types.h>
extern kern_return_t _start(kmod_info_t *, void *);
extern kern_return_t _stop(kmod_info_t *, void *);
__private_extern__ kern_return_t AppleALC_kern_start(kmod_info_t *, void *);
__private_extern__ kern_return_t AppleALC_kern_stop(kmod_info_t *, void *);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(as.vit9696.AppleALC, "$VER", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = AppleALC_kern_start;
__private_extern__ kmod_stop_func_t *_antimain = AppleALC_kern_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
EOF
clang -arch x86_64 -mkernel -nostdinc -I MacKernelSDK/Headers -DKERNEL -mmacosx-version-min=10.13 -c $OUT/info.c -o $OUT/info.o
objs+=$OUT/info.o

echo "LD build/AppleALC"
clang++ -arch x86_64 -mkernel -nostdlib -Xlinker -kext -Xlinker -static -mmacosx-version-min=10.13 \
	$objs MacKernelSDK/Library/x86_64/libkmod.a -lcc_kext -o build/AppleALC
strip -x build/AppleALC 2>/dev/null || true
ls -la build/AppleALC

# Assemble the bundle: Info.plist from the template + merged PinConfigs, as Tools/merge_pinconfigs.sh does.
echo "PLIST build/AppleALC.kext"
rm -rf build/AppleALC.kext
mkdir -p build/AppleALC.kext/Contents/MacOS
cp build/AppleALC build/AppleALC.kext/Contents/MacOS/AppleALC
python3 -I - "$VER" <<'PY'
import plistlib, re, sys
ver = sys.argv[1]
subst = {'EXECUTABLE_NAME': 'AppleALC', 'PRODUCT_NAME': 'AppleALC', 'PRODUCT_BUNDLE_IDENTIFIER': 'as.vit9696.AppleALC',
         'MODULE_VERSION': ver, 'CURRENT_PROJECT_VERSION': ver, 'DEVELOPMENT_LANGUAGE': 'English', 'PRODUCT_BUNDLE_PACKAGE_TYPE': 'KEXT'}
tpl = open('AppleALC/AppleALC-Info.plist').read()
tpl = re.sub(r'\$\((\w+)(?::\w+)?\)', lambda m: subst[m.group(1)], tpl)
info = plistlib.loads(tpl.encode())
pins = plistlib.load(open('Resources/PinConfigs.kext/Contents/Info.plist', 'rb'))
info['IOKitPersonalities']['as.vit9696.AppleALC'] = pins['IOKitPersonalities']['as.vit9696.AppleALC']
info.get('OSBundleLibraries', {}).pop('as.vit9696.PinConfigs', None)
info.setdefault('CFBundleSupportedPlatforms', ['MacOSX'])
info.setdefault('LSMinimumSystemVersion', '10.6')
plistlib.dump(info, open('build/AppleALC.kext/Contents/Info.plist', 'wb'))
PY
plutil -lint build/AppleALC.kext/Contents/Info.plist
