SHELL:="/bin/bash"
PREFIX="./build"

all: cephtools doc

cephtools: src/head src/subcommands* src/main
	mkdir -p "$(DESTDIR)$(PREFIX)/bin"
	cat $^ > "$(DESTDIR)$(PREFIX)/bin/$@"
	chmod u+x "$(DESTDIR)$(PREFIX)/bin/$@"

doc: doc/*
	mkdir -p "$(DESTDIR)$(PREFIX)/share/man/man1"
	# Convert markdown to man page format
	MODULEPATH="/home/lmnp/knut0297/software/modulesfiles:$(MODULEPATH)" module load ronn-ng; \
	ronn $^ --output-dir "$(DESTDIR)$(PREFIX)/share/man/man1"
	mkdir -p "$(DESTDIR)$(PREFIX)/share/man_html"
	mv $(DESTDIR)$(PREFIX)/share/man/man1/*html "$(DESTDIR)$(PREFIX)/share/man_html"

clean:
	rm -rf "$(DESTDIR)$(PREFIX)"

.PHONY: all clean doc
