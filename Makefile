.PHONY: build install uninstall fallback test project clean
build:    ; ./scripts/build.sh
install:  ; ./scripts/install.sh
uninstall: ; ./scripts/uninstall.sh
fallback: ; ./scripts/build-fallback.sh
test:     ; ./scripts/selftest.sh
project:  ; python3 tools/gen_xcodeproj.py
clean:    ; rm -rf build
