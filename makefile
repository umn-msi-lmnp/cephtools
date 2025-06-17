SHELL := /bin/bash
PREFIX = ./build
DESTDIR=
BUILD=$(DESTDIR)$(PREFIX)


# Update the version variables, and make the vaiables available here
GIT_CURRENT_BRANCH := $(shell git symbolic-ref --short HEAD)
GIT_LATEST_COMMIT := $(shell git rev-parse HEAD)
GIT_LATEST_COMMIT_SHORT := $(shell git rev-parse HEAD | cut -c1-7)
GIT_LATEST_COMMIT_DIRTY := $(shell git diff --quiet || echo "-dirty")
GIT_LATEST_COMMIT_DATETIME := $(shell git show -s --format="%cI" "$(GIT_LATEST_COMMIT)")
GIT_REMOTE := $(shell git ls-remote --get-url)




# Generate file paths for some targets
MAN_NAMES:=cephtools.1 cephtools-dd2ceph.1 cephtools-panfs2ceph.1 cephtools-bucketpolicy.1
MAN_TARGETS:=$(MAN_NAMES:%=$(BUILD)/share/man/man1/%)
MAN_TARGETS_HTML:=$(MAN_NAMES:%=$(BUILD)/share/man_html/%.html)
DOC_NAMES:=vignette_dd2ceph.html vignette_getting_started.html
DOC_TARGETS:=$(DOC_NAMES:%=$(BUILD)/share/doc/%)
# file path for dd2dr_commands.sh
SRC_1_NAMES:=dd2dr_commands.sh
SRC_1_TARGETS:=$(SRC_1_NAMES:%=$(BUILD)/bin/%)
SRC_1_PREREQUISITES:=$(SRC_1_NAMES:%=./src/%)

.PHONY: all copy_files
# all: $(BUILD)/bin/cephtools $(MAN_TARGETS) $(MAN_TARGETS_HTML) $(DOC_TARGETS)
all: $(BUILD)/bin/cephtools copy_files update_version

# Combine all the bash fragments into a single script
$(BUILD)/bin/cephtools: src/head_1 src/version src/head_2 src/subcommands_panfs2ceph src/subcommands_dd2ceph src/subcommands_dd2dr src/subcommands_bucketpolicy src/subcommands_filesinbackup src/subcommands_default src/main
	mkdir -p $(BUILD)/bin
	cat $^ > $@
	chmod u+x $@

# Keep dd2dr_commands.sh separate
copy_files: ./src/dd2dr_commands.sh
	@mkdir -p $(BUILD)/bin
	@cp $^ $(BUILD)/bin
	@chmod u+x $^

#
# # Convert markdown (ronn format) to man page format
# $(BUILD)/share/man/man1/%: doc/%.ronn
# 	mkdir -p $(BUILD)/share/man/man1; \
# 	MODULEPATH="/home/lmnp/knut0297/software/modulesfiles:$(MODULEPATH)" module load ronn-ng; \
# 	ronn --roff $^ --output-dir $(BUILD)/share/man/man1
#
# # Convert markdown (ronn format) to HTML format
# $(BUILD)/share/man_html/%.html: doc/%.ronn
# 	mkdir -p $(BUILD)/share/man_html; \
# 	MODULEPATH="/home/lmnp/knut0297/software/modulesfiles:$(MODULEPATH)" module load ronn-ng; \
# 	ronn --html $^ --output-dir $(BUILD)/share/man_html
#
# # Convert markdown vignettes to HTML format
# $(BUILD)/share/doc/%.html: doc/%.md
# 	mkdir -p $(BUILD)/share/doc; \
# 	MODULEPATH="/home/lmnp/knut0297/software/modulesfiles:$(MODULEPATH)" module load pandoc; \
# 	pandoc -f markdown -t html $^ -o $@ --self-contained 
#
#


# Update target files with latest version data
update_version: $(BUILD)/bin/cephtools
	sed -i 's|^GIT_CURRENT_BRANCH=.*|GIT_CURRENT_BRANCH=$(GIT_CURRENT_BRANCH)|g' $^
	sed -i 's|^GIT_LATEST_COMMIT=.*|GIT_LATEST_COMMIT=$(GIT_LATEST_COMMIT)|g' $^
	sed -i 's|^GIT_LATEST_COMMIT_SHORT=.*|GIT_LATEST_COMMIT_SHORT=$(GIT_LATEST_COMMIT_SHORT)|g' $^
	sed -i 's|^GIT_LATEST_COMMIT_DIRTY=.*|GIT_LATEST_COMMIT_DIRTY=$(GIT_LATEST_COMMIT_DIRTY)|g' $^
	sed -i 's|^GIT_LATEST_COMMIT_DATETIME=.*|GIT_LATEST_COMMIT_DATETIME=$(GIT_LATEST_COMMIT_DATETIME)|g' $^
	sed -i 's|^GIT_REMOTE=.*|GIT_REMOTE=$(GIT_REMOTE)|g' $^



clean:
	rm -rf $(BUILD)
