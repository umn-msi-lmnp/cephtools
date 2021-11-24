PREFIX="./build"

all: cephtools doc

cephtools: src/head src/subcommands* src/main
	mkdir -p "$(DESTDIR)$(PREFIX)/bin"
	cat $^ > "$(DESTDIR)$(PREFIX)/bin/$@"
	chmod u+xs "$(DESTDIR)$(PREFIX)/bin/$@"

doc: doc/*
	mkdir -p "$(DESTDIR)$(PREFIX)/share/man/man1"
	cp $^ "$(DESTDIR)$(PREFIX)/share/man/man1"

clean:
	rm -rf "$(DESTDIR)$(PREFIX)"

.PHONY: all clean doc


   
