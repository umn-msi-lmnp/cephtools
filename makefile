SHELL:=/bin/bash
PREFIX=./build
DESTDIR=
BUILD=$(DESTDIR)$(PREFIX)

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
all: $(BUILD)/bin/cephtools copy_files

# Combine all the bash fragments into a single script
$(BUILD)/bin/cephtools: src/head_1 src/version src/head_2 src/subcommands* src/main
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
clean:
	rm -rf $(BUILD)
