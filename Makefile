ifneq ($(wildcard .git),)
	VERSION      := $(shell git describe --abbrev=6 --long --dirty --always --tags --first-parent | sed s/-/./)
	VERSIONSHORT := $(shell echo v${VERSION} | sed 's/-g[0-9a-f]*//; s/-dirty/D/')
endif

export PATH:=/cygdrive/c/Hwdev/sjasmplus/:/cygdrive/e/Emulation/ZX Spectrum/Emuls/Es.Pectrum/:${PATH}

# Set MEM=1024 to enable full Pentagon 1024SL support (extra 512KB via #7FFD bit5,
# unlocked through #EFF7). Without it the binary still auto-detects 128K/512K at
# runtime and supports MIDI files up to the detected RAM (64KB on 128K, ~448KB on 512K).
ifeq (${MEM},1024)
	MEMDEF := -DPENTAGON_1024
endif

SJOPTS = --nologo --fullpath --outprefix=build/ -DVERSION_DEF=\"${VERSION}\" -DVERSIONSHORT_DEF=\"${VERSIONSHORT}\" ${MEMDEF}

.PHONY: all clean run

all:
	@mkdir -p build
	sjasmplus --msg=war --lst=build/main.lst --exp=build/main.exp --sld=build/main.sld ${SJOPTS} src/main.asm
	sjasmplus --msg=err --lst=build/build.lst ${SJOPTS} src/build.asm

clean:
	rm -rf build/ .tmp/

run:
	EsPectrum build/main.trd

-include Makefile.local
