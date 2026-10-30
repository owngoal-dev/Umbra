ARCHS = arm64
# RootHide's package scheme otherwise hardcodes the iOS package architecture.
ifeq ($(UMBRA_PLATFORM),ios)
DEB_ARCH = iphoneos-arm64e
else
override THEOS_PACKAGE_ARCH := $(UMBRA_DEB_ARCH)
endif
INSTALL_TARGET_PROCESSES = Umbra
THEOS_PACKAGE_SCHEME = roothide
FINALPACKAGE ?= 1
DEBUG ?= 0

include $(THEOS)/makefiles/common.mk

XCODE_SCHEME = $(UMBRA_SCHEME)
XCODEPROJ_NAME = Umbra
Umbra_DESTINATION = $(UMBRA_DESTINATION)
Umbra_XCODEFLAGS = MARKETING_VERSION=$(THEOS_PACKAGE_BASE_VERSION) \
	$(UMBRA_DEPLOYMENT_SETTING) CODE_SIGN_IDENTITY="" AD_HOC_CODE_SIGNING_ALLOWED=YES
Umbra_XCODEOPTS = -derivedDataPath "$(BUILD_DIR)/$(UMBRA_PLATFORM)-package"
Umbra_XCODE_SCHEME = $(XCODE_SCHEME)
Umbra_CODESIGN_FLAGS = -Sentitlements.plist
Umbra_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/xcodeproj.mk

before-all::
	echo "#define VARCLEANRULESHASH" $$(cksum -o 3 Umbra/VarCleanRules.json | awk '{print $$1}') > Umbra/VarCleanRules.h

clean::
	rm -rf ./packages/*

before-package::
	ldid -M -S./nickchan.entitlements $(THEOS_STAGING_DIR)/Applications/Umbra.app/Umbra

after-install::
	install.exec 'uiopen -b wiki.qaq.umbra'
