.DEFAULT_GOAL := all

UMBRA_PLATFORM ?= ios
BUILD_DIR ?= $(CURDIR)/.build
XCODEBUILD ?= xcodebuild

include Makefiles/Platform.mk

# Only packaging and installation require Theos.
STANDALONE_GOALS := format format-check check archive ipa
REQUESTED_GOALS := $(if $(MAKECMDGOALS),$(MAKECMDGOALS),all)
ifneq ($(filter-out $(STANDALONE_GOALS),$(REQUESTED_GOALS)),)
include Makefiles/Package.mk
endif

include Makefiles/Archive.mk
include Makefiles/Quality.mk
