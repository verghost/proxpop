.PHONY: install
install:
	install -D -m 644 resources.default -t $(DESTDIR)/usr/share/proxpop/
	install -D -m 755 proxpop.sh $(DESTDIR)/usr/bin/proxpop.sh
