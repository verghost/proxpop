.PHONY: install
install:
	install -D -m 644 proxychains.template -t $(DESTDIR)/usr/share/proxpop/
	install -D -m 644 resources.default -t $(DESTDIR)/usr/share/proxpop/
	install -D -m 755 dnsenum.pl $(DESTDIR)/usr/bin/proxpop
