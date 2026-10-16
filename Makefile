UMBRA_PLATFORM ?= ios
UMBRA_DEPLOYMENT_TARGET ?= 15.0
BUILD_DIR ?= $(CURDIR)/.build
XCODEBUILD ?= xcodebuild

ifeq ($(UMBRA_PLATFORM),ios)
TARGET = iphone:latest:$(UMBRA_DEPLOYMENT_TARGET)
UMBRA_SDK = iphoneos
UMBRA_DESTINATION = generic/platform=iOS
UMBRA_DEPLOYMENT_SETTING = IPHONEOS_DEPLOYMENT_TARGET=$(UMBRA_DEPLOYMENT_TARGET)
UMBRA_DEB_ARCH = iphoneos-arm64e
else ifeq ($(UMBRA_PLATFORM),tvos)
TARGET = appletv:latest:$(UMBRA_DEPLOYMENT_TARGET)
UMBRA_SDK = appletvos
UMBRA_DESTINATION = generic/platform=tvOS
UMBRA_DEPLOYMENT_SETTING = TVOS_DEPLOYMENT_TARGET=$(UMBRA_DEPLOYMENT_TARGET)
UMBRA_DEB_ARCH = appletvos-arm64e
else
$(error UMBRA_PLATFORM must be ios or tvos)
endif

ARCHIVE_PATH ?= $(BUILD_DIR)/Umbra-$(UMBRA_PLATFORM).xcarchive
IPA_PATH ?= $(BUILD_DIR)/Umbra-$(UMBRA_PLATFORM)-unsigned.ipa

# Formatting, checks and unsigned archives do not require Theos.
ifneq ($(filter-out format format-check check archive ipa,$(if $(MAKECMDGOALS),$(MAKECMDGOALS),all)),)
ARCHS = arm64
# RootHide's package scheme otherwise hardcodes the iOS package architecture.
override THEOS_PACKAGE_ARCH := $(UMBRA_DEB_ARCH)
INSTALL_TARGET_PROCESSES = Umbra
THEOS_PACKAGE_SCHEME = roothide
FINALPACKAGE ?= 1
DEBUG ?= 0

include $(THEOS)/makefiles/common.mk

XCODE_SCHEME = Umbra
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
endif

.PHONY: archive ipa
archive:
	$(XCODEBUILD) -project Umbra.xcodeproj -scheme Umbra -configuration Release \
		-sdk $(UMBRA_SDK) -destination '$(UMBRA_DESTINATION)' \
		-derivedDataPath "$(BUILD_DIR)/$(UMBRA_PLATFORM)" -archivePath "$(ARCHIVE_PATH)" \
		CODE_SIGNING_ALLOWED=NO ARCHS=arm64 $(UMBRA_DEPLOYMENT_SETTING) archive

ipa: archive
	python3 Tools/package-ipa.py "$(ARCHIVE_PATH)/Products/Applications/Umbra.app" "$(IPA_PATH)"

SWIFT_FORMAT ?= xcrun swift-format
CLANG_FORMAT ?= clang-format
SWIFT_SOURCES := $(wildcard Umbra/*.swift Umbra/Platform/*.swift Tests/*.swift Tools/*.swift)
CLANG_SOURCES := $(filter-out Umbra/NSJSONSerialization+Comments.h Umbra/NSJSONSerialization+Comments.m,$(wildcard Umbra/*.[mh] Umbra/AppDataCleaner/*.[mh] Umbra/Platform/*.h Tests/*.m))

.PHONY: format format-check check
format:
	$(SWIFT_FORMAT) format --in-place $(SWIFT_SOURCES)
	$(CLANG_FORMAT) -i $(CLANG_SOURCES)

format-check:
	$(SWIFT_FORMAT) lint --strict $(SWIFT_SOURCES)
	$(CLANG_FORMAT) --dry-run --Werror $(CLANG_SOURCES)

check:
	python3 Tests/check_ipa.py
	python3 Tests/check_localizations.py
	python3 Tests/check_environment_summary.py
	python3 Tests/check_service_ports.py
	./Tests/check.sh
