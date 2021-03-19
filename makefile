sysdelta:
	fpc -O2 sysdelta.pas

install: sysdelta
	mkdir -p ${HOME}/.local/bin
	cp sysdelta ${HOME}/.local/bin

uninstall: 
	rm ${HOME}/.local/bin/sysdelta

clear:
	rm sysdelta sysdelta.o
