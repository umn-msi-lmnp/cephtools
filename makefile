SHELL := /bin/bash

# Paths
PREFIX     := ./build
DESTDIR    :=
BUILD      := $(DESTDIR)$(PREFIX)
MODULEPATH := /projects/standard/lmnp/knut0297/software/modulesfiles

# Git Metadata
GIT_CURRENT_BRANCH        := $(shell git symbolic-ref --short HEAD)
GIT_LATEST_COMMIT         := $(shell git rev-parse HEAD)
GIT_LATEST_COMMIT_SHORT   := $(shell echo $(GIT_LATEST_COMMIT) | cut -c1-7)
GIT_LATEST_COMMIT_DIRTY   := $(shell git diff --quiet || echo "-dirty")
GIT_LATEST_COMMIT_DATETIME:= $(shell git show -s --format="%cI" $(GIT_LATEST_COMMIT))
GIT_REMOTE                := $(shell git ls-remote --get-url)

# File Lists
MAN_NAMES       := cephtools.1 cephtools-dd2ceph.1 cephtools-panfs2ceph.1 cephtools-bucketpolicy.1
MAN_TARGETS     := $(MAN_NAMES:%=$(BUILD)/share/man/man1/%)
MAN_TARGETS_HTML:= $(MAN_NAMES:%=$(BUILD)/share/man_html/%.html)
DOC_NAMES       := vignette_dd2ceph.html vignette_getting_started.html vignette_panfs2ceph.html vignette_bucketpolicy.html
DOC_TARGETS     := $(DOC_NAMES:%=$(BUILD)/share/doc/%)
SCRIPT_TARGET   := $(BUILD)/bin/cephtools
SRC_1_NAMES     := dd2dr_commands.sh
SRC_1_TARGETS   := $(SRC_1_NAMES:%=$(BUILD)/bin/%)
SRC_1_SRC       := $(SRC_1_NAMES:%=src/%)

# Top-level Targets
.PHONY: all cephtools copy_files update_version docs clean

all: cephtools copy_files update_version

cephtools: $(SCRIPT_TARGET)

$(SCRIPT_TARGET): \
	src/head_1 \
	src/version \
	src/head_2 \
	src/subcommands_panfs2ceph \
	src/subcommands_dd2ceph \
	src/subcommands_dd2dr \
	src/subcommands_bucketpolicy \
	src/subcommands_filesinbackup \
	src/subcommands_default \
	src/main
	mkdir -p $(dir $@)
	cat $^ > $@
	chmod u+x $@

copy_files: $(SRC_1_SRC)
	mkdir -p $(BUILD)/bin
	cp $^ $(BUILD)/bin
	chmod u+x $(BUILD)/bin/$(notdir $^)

docs: $(MAN_TARGETS) $(MAN_TARGETS_HTML) $(DOC_TARGETS)

# Ronn to man
$(BUILD)/share/man/man1/%: doc/%.ronn
	MODULEPATH="$(MODULEPATH):$$MODULEPATH" module load ronn-ng; \
	if ! ronn --version >/dev/null 2>&1; then \
		echo "Warning: 'ronn' not usable. Skipping $@."; \
	else \
		mkdir -p $(dir $@); \
		ronn --roff $< --output-dir $(dir $@); \
	fi

# Ronn to HTML
$(BUILD)/share/man_html/%.html: doc/%.ronn
	MODULEPATH="$(MODULEPATH):$$MODULEPATH" module load ronn-ng; \
	if ! ronn --version >/dev/null 2>&1; then \
		echo "Warning: 'ronn' not usable. Skipping $@."; \
	else \
		mkdir -p $(dir $@); \
		ronn --html $< --output-dir $(dir $@); \
	fi

# Pandoc for vignettes
$(BUILD)/share/doc/%.html: doc/%.md
	MODULEPATH="$(MODULEPATH):$$MODULEPATH" module load pandoc; \
	TITLE=$(basename $(basename $(notdir $@))); \
	if ! pandoc --version >/dev/null 2>&1; then \
		echo "Warning: 'pandoc' not usable. Skipping $@."; \
	else \
		mkdir -p $(dir $@); \
		pandoc -f markdown -t html $< -o $@ --embed-resources --standalone --metadata title="$$TITLE"; \
	fi

update_version: $(SCRIPT_TARGET)
	sed -i 's|^GIT_CURRENT_BRANCH=.*|GIT_CURRENT_BRANCH=$(GIT_CURRENT_BRANCH)|' $<
	sed -i 's|^GIT_LATEST_COMMIT=.*|GIT_LATEST_COMMIT=$(GIT_LATEST_COMMIT)|' $<
	sed -i 's|^GIT_LATEST_COMMIT_SHORT=.*|GIT_LATEST_COMMIT_SHORT=$(GIT_LATEST_COMMIT_SHORT)|' $<
	sed -i 's|^GIT_LATEST_COMMIT_DIRTY=.*|GIT_LATEST_COMMIT_DIRTY=$(GIT_LATEST_COMMIT_DIRTY)|' $<
	sed -i 's|^GIT_LATEST_COMMIT_DATETIME=.*|GIT_LATEST_COMMIT_DATETIME=$(GIT_LATEST_COMMIT_DATETIME)|' $<
	sed -i 's|^GIT_REMOTE=.*|GIT_REMOTE=$(GIT_REMOTE)|' $<

clean:
	rm -rf $(BUILD)
