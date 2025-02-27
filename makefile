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

.PHONY: all
# all: $(BUILD)/bin/cephtools $(MAN_TARGETS) $(MAN_TARGETS_HTML) $(DOC_TARGETS)
all: $(BUILD)/bin/cephtools 

# Combine all the bash fragments into a single script
$(BUILD)/bin/cephtools: src/head_1 src/version src/head_2 src/subcommands* src/main
	mkdir -p $(BUILD)/bin
	cat $^ > $@
	chmod u+x $@
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
