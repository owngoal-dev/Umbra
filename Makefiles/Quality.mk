SWIFT_FORMAT ?= swiftformat
CLANG_FORMAT ?= clang-format
SWIFT_SOURCES := Umbra UmbraTV Tools Tests
CLANG_SOURCES := $(wildcard Umbra/*.[mh] Umbra/AppDataCleaner/*.[mh] Umbra/Platform/*.h Tests/*.m)

.PHONY: format format-check check
format:
	$(SWIFT_FORMAT) $(SWIFT_SOURCES)
	$(CLANG_FORMAT) -i $(CLANG_SOURCES)

format-check:
	$(SWIFT_FORMAT) $(SWIFT_SOURCES) --lint
	$(CLANG_FORMAT) --dry-run --Werror $(CLANG_SOURCES)

check:
	python3 Tests/check_ipa.py
	python3 Tests/check_localizations.py
	python3 Tests/check_environment_summary.py
	python3 Tests/check_service_ports.py
	./Tests/check.sh
