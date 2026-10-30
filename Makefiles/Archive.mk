ARCHIVE_PATH ?= $(BUILD_DIR)/Umbra-$(UMBRA_PLATFORM).xcarchive
IPA_PATH ?= $(BUILD_DIR)/Umbra-$(UMBRA_PLATFORM)-unsigned.ipa

.PHONY: archive ipa
archive:
	$(XCODEBUILD) -project Umbra.xcodeproj -scheme $(UMBRA_SCHEME) -configuration Release \
		-sdk $(UMBRA_SDK) -destination '$(UMBRA_DESTINATION)' \
		-derivedDataPath "$(BUILD_DIR)/$(UMBRA_PLATFORM)" -archivePath "$(ARCHIVE_PATH)" \
		CODE_SIGNING_ALLOWED=NO ARCHS=arm64 $(UMBRA_DEPLOYMENT_SETTING) archive

ipa: archive
	python3 Tools/package-ipa.py "$(ARCHIVE_PATH)/Products/Applications/Umbra.app" "$(IPA_PATH)"
