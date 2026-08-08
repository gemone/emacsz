# ncurses-config: ncurses configure/make-generated artifacts

This directory pins the files ncurses 6.4 normally generates during
`./configure` + `make` (with autotools).  They are committed so
`zig build` can compile the library with `zig cc` alone (no autotools,
no `make`, no awk/perl/shell generators).

## Sources

- `include/*.h` - configure/make-generated headers: `config.h`,
  `curses.h`, `term.h`, `ncurses_cfg.h`, `ncurses_def.h`,
  `ncurses_dll.h`, `termcap.h`, `unctrl.h`, `hashsize.h`,
  `parametrized.h`, plus the form/menu/panel/eti headers.
- `ncurses/*.c` - make-generated capability tables and stubs:
  `codes.c`, `comp_captab.c`, `comp_userdefs.c`, `expanded.c`,
  `fallback.c`, `lib_gen.c`, `lib_keyname.c`, `names.c`, `unctrl.c`,
  and `init_keytry.h`.
- `ncurses-sources.txt` - the 140 tarball C files the reference build
  compiled into libncurses (used via build.zig `@embedFile`).
- `ncurses-generated-sources.txt` - the 9 generated C files above
  (resolved against `tools/ncurses-config/ncurses/`).

## How they were regenerated

Reference build on macOS (aarch64), compiler `CC="zig cc"`:

```
./configure --prefix=/tmp/ref-prefix --without-ada --without-cxx \
  --without-cxx-binding --without-manpages --without-progs \
  --without-tests --without-tools --without-develop --without-dlsym \
  --disable-shared --enable-static --without-widec --enable-termcap \
  --with-terminfo-dirs=/usr/share/terminfo \
  --with-default-terminfo-dir=/usr/share/terminfo \
  --disable-db-install --disable-stripping
make libs
```

The generated headers/tables and the `make`-derived object list were
copied from the build tree.  Bumping the ncurses version or porting to a
new OS means re-running this reference build and updating these files.
