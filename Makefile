.PHONY: install helper app probe uninstall clean

install: helper app

helper:
	scripts/install-helper.sh

app:
	scripts/install-app.sh

probe: build/ignix-probe

build/ignix-probe: tools/probe.swift
	mkdir -p build
	swiftc -O $< -o $@

uninstall:
	scripts/uninstall.sh

clean:
	rm -rf build
