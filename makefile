SHELL:=/bin/bash
PREFIX=./build
DESTDIR=
BUILD=$(DESTDIR)$(PREFIX)

# Generate file paths for some targets
MAN_NAMES:=cephtools.1 cephtools-panfs2ceph.1
MAN_TARGETS:=$(MAN_NAMES:%=$(BUILD)/share/man/man1/%)

.PHONY: all
#all: $(BUILD)/bin/cephtools $(BUILD)/share/man/man1/cephtools.1 $(BUILD)/share/man/man1/cephtools-panfs2ceph.1
all: $(BUILD)/bin/cephtools $(MAN_TARGETS)

# Combine all the bash fragments into a single script
$(BUILD)/bin/cephtools: src/head_1 src/version src/head_2 src/subcommands* src/main
	mkdir -p $(BUILD)/bin
	cat $^ > $@
	chmod u+x $@

# Convert markdown (ronn format) to man page format
$(BUILD)/share/man/man1/%: doc/%.ronn
	mkdir -p $(BUILD)/share/man/man1; \
	MODULEPATH="/home/lmnp/knut0297/software/modulesfiles:$(MODULEPATH)" module load ronn-ng; \
	ronn --roff $^ --output-dir $(BUILD)/share/man/man1

clean:
	rm -rf $(BUILD)
