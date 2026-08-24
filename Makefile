SHELL := /bin/sh

PREFIX ?= /usr
DESTDIR ?=
PROJECT := quickshell-share-picker
SHAREDIR := $(DESTDIR)$(PREFIX)/share/$(PROJECT)
DOCDIR := $(DESTDIR)$(PREFIX)/share/doc/$(PROJECT)
BINDIR := $(DESTDIR)$(PREFIX)/bin
PYTHON ?= python3
QMLLINT ?= $(shell if test -x /usr/lib/qt6/bin/qmllint; then printf '%s' /usr/lib/qt6/bin/qmllint; else command -v qmllint 2>/dev/null; fi)

SHELL_FILES := bin/quickshell-share-picker scripts/create-dist scripts/offscreen-smoke scripts/run-mock tests/helpers/fake-qs tests/helpers/fake-slurp
QML_FILES := src/quickshell/PickerPanelWindow.qml src/quickshell/PickerSmokeWindow.qml src/quickshell/PickerWindow.qml src/quickshell/shell.qml

.PHONY: all check clean dist format format-check install lint lint-qml lint-shell smoke test uninstall

all: check

check: format-check lint test smoke

format:
	$(PYTHON) scripts/check-format --fix

format-check:
	$(PYTHON) scripts/check-format

lint: lint-shell lint-qml

lint-shell:
	@for file in $(SHELL_FILES); do sh -n "$$file"; done
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SHELL_FILES); \
	elif [ "$(REQUIRE_SHELLCHECK)" = 1 ]; then \
		echo "shellcheck is required" >&2; exit 1; \
	else \
		echo "SKIP shellcheck (not installed)"; \
	fi

lint-qml:
	@if [ -n "$(QMLLINT)" ] && [ -x "$(QMLLINT)" ]; then \
		"$(QMLLINT)" -W 0 $(QML_FILES); \
	elif [ "$(REQUIRE_QMLLINT)" = 1 ]; then \
		echo "qmllint is required" >&2; exit 1; \
	else \
		echo "SKIP qmllint (not installed)"; \
	fi

test:
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) -m unittest discover -s tests -v

smoke:
	./scripts/offscreen-smoke

dist: format-check
	./scripts/create-dist

install:
	install -Dm755 bin/quickshell-share-picker "$(BINDIR)/quickshell-share-picker"
	install -Dm644 src/quickshell/shell.qml "$(SHAREDIR)/quickshell/shell.qml"
	install -Dm644 src/quickshell/PickerPanelWindow.qml "$(SHAREDIR)/quickshell/PickerPanelWindow.qml"
	install -Dm644 src/quickshell/PickerSmokeWindow.qml "$(SHAREDIR)/quickshell/PickerSmokeWindow.qml"
	install -Dm644 src/quickshell/PickerWindow.qml "$(SHAREDIR)/quickshell/PickerWindow.qml"
	install -Dm644 src/lib/protocol.py "$(SHAREDIR)/lib/protocol.py"
	install -Dm644 src/fixtures/mock-session.json "$(SHAREDIR)/fixtures/mock-session.json"
	install -Dm644 README.md "$(DOCDIR)/README.md"
	install -Dm644 CHANGELOG.md "$(DOCDIR)/CHANGELOG.md"
	install -Dm644 LICENSE "$(DOCDIR)/LICENSE"
	install -Dm644 NOTICE "$(DOCDIR)/NOTICE"

uninstall:
	rm -f "$(BINDIR)/quickshell-share-picker"
	rm -rf "$(SHAREDIR)" "$(DOCDIR)"

clean:
	rm -rf dist src/lib/__pycache__ tests/__pycache__
