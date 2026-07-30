# una-nix

Nix toolchain and app builder for the [UNA Watch SDK](https://github.com/UNAWatch/una-sdk).

Build UNA Watch apps reproducibly on Linux and macOS — no STM32CubeIDE, no ST
account, no Windows.

```bash
nix develop            # toolchain + UNA_SDK, via direnv or directly
nix build .#hello      # -> result/Hello_0.1.0.uapp
```

## Why this exists

The SDK's own setup guide calls the ST-patched `arm-none-eabi-gcc` from
STM32CubeIDE/CubeCLT **"CRITICAL"**, warning that distro toolchains fail with
missing newlib syscall stubs (`_write`, `_close`).

**That does not apply to the CMake build path.** `cmake/una-app.cmake` compiles
and links with `-nostdlib -nodefaultlibs -nostartfiles` against a vendored
`Libs/Source/AppSystem/Libc++/libstdc++.a`. Newlib's syscall layer is never
linked, so its stubs are never needed. The stock nixpkgs `gcc-arm-embedded`
builds a byte-valid `.uapp`.

Exactly one thing blocks it: `una-app.cmake` passes `-fcyclomatic-complexity`,
a flag that exists only in ST's GNU Tools for STM32 fork. `patches/0001-*` makes
it opt-in (`-DUNA_ENABLE_CYCLOMATIC_COMPLEXITY=ON` restores it for ST users).

## Requirements

Nix with flakes enabled. Nothing else — no SDK checkout, no `pip install`, no
`UNA_SDK` export. The SDK is a pinned flake input, patched and realized into the
store.

## Usage

### Build an app

```bash
nix build .#hello
ls result/            # Hello_0.1.0.uapp
```

### Interactive builds

Inside `nix develop`, `una-build` wraps CMake with the two flags that keep the
interactive and sandboxed paths identical:

```bash
una-build apps/hello/Software/Apps/Hello-CMake 0.1.0
```

It pins `-DBUILD_VERSION` and `-DUNA_PYTHON_EXECUTABLE`. Both matter — see
[Gotchas](#gotchas).

### Run the simulator

**x86_64-linux only.**

```bash
nix run .#sim-hello
```

The vendored TouchGFX artifacts (`libtouchgfx.a`, `imageconvert.out`,
`fontconvert.out`) are prebuilt x86_64 ELF from the Ubuntu 16.04 era. There is
no macOS or aarch64 build, so on Apple Silicon you get the firmware path only.

### Host unit tests

```bash
nix flake check
```

Runs the SDK's own GoogleTest suite. `patches/0002-*` swaps its `FetchContent`
googletest pull for `find_package(GTest)`, since sandboxed builds have no
network.

## Deploying to the watch

There is no flasher and no debug probe. Deployment is a file copy:

1. Connect the watch over USB and wait for mass storage to appear (it may take a
   moment — running apps flush data first).
2. Create `Apps/<AppName>/` on the watch volume.
3. Copy the `.uapp` into it.
4. Eject safely, disconnect, and power-cycle the watch.
5. Press the top-right button to find the app.

`.uapp` packages carry a CRC, not a signature, so sideloading needs no developer
account.

## Adding an app

1. Copy the seed app: `cp -r apps/hello apps/myapp`
2. Rename `Software/Apps/Hello-CMake` to `Software/Apps/MyApp-CMake`.
3. In its `CMakeLists.txt`, set `APP_NAME`, `APP_USER_NAME`, and a unique
   `APP_ID` (16 uppercase hex chars):
   ```bash
   python3 -c 'import hashlib; print(hashlib.md5(b"MyApp").hexdigest().upper()[:16])'
   ```
   Or take one from the [developer portal](https://apps.unawatch.com) if you
   intend to publish.
4. Add it to `nix/apps.nix`:
   ```nix
   packages.myapp = mkUnaApp {
     pname = "myapp";
     version = "0.1.0";
     src = ../apps/myapp;
     cmakeDir = "Software/Apps/MyApp-CMake";
   };
   ```

`apps/hello` is the SDK's `Alarm` example, rebranded. It was chosen because it
has a TouchGFX GUI, so it exercises the simulator path too.

Editing screen layouts still requires TouchGFX Designer, which is Windows-only.
Building does not — each app commits its `generated/` output, so the GUI compiles
and runs from a checkout alone. Glance-type apps skip TouchGFX entirely.

## Layout

| Path | Purpose |
|---|---|
| `nix/sdk.nix` | Patched SDK tree; exports `unaSdk` and `unaPython` |
| `nix/lib.nix` | `mkUnaApp` — app directory to `.uapp` |
| `nix/apps.nix` | App package definitions |
| `nix/devshell.nix` | devShell and the `una-build` wrapper |
| `nix/checks.nix` | Artifact check and SDK host tests |
| `nix/simulator.nix` | TouchGFX simulator (x86_64-linux) |
| `patches/` | Applied to the SDK input |
| `apps/` | Watch apps |

Upgrade the SDK with `nix flake update una-sdk`. Patch drift shows up as a
patch-apply failure, which is the signal you want.

## Gotchas

These are designed around rather than documented at, but they explain the code:

**CMake caches Python's store path.** `una-app.cmake` runs
`find_program(UNA_PYTHON_EXECUTABLE ...)` and caches the result. After a devShell
update the cached path still exists but no longer carries `pyelftools`/`pillow`,
and the build fails at packing with `ModuleNotFoundError: No module named
'elftools'` until the build directory is reconfigured. Both `mkUnaApp` and
`una-build` pin the interpreter instead.

**The version script shells out to git.** `una_app_setup_version` invokes
`una-version.sh`, which runs `git config --global safe.directory` and fails
outside a writable `HOME`. It returns early when `BUILD_VERSION` is already
defined, so both paths pass it explicitly.

**TouchGFX assumes apps live inside the SDK tree.** `config/gcc/app.mk` hardcodes
`touchgfx_path := ../../../../../../ThirdParty/touchgfx`, a relative offset that
only resolves for apps at `<sdk>/Examples/Apps/<App>/Software/Apps/TouchGFX-GUI`.
Out-of-tree apps need it overridden on the make command line —
`nix/simulator.nix` does this.

## Status

The firmware path is verified end-to-end on aarch64-darwin and builds a valid
`.uapp`. **The simulator has not yet been built on real hardware** — it is
verified only by Nix evaluation. See `nix/simulator.nix` for what to check on
first build.

## License

The Nix code here is MIT. The SDK it consumes is MIT with separately-licensed
third-party components under `ThirdParty/` — see the
[SDK's licensing](https://github.com/UNAWatch/una-sdk/blob/main/THIRD-PARTY-LICENSES.md).
"UNA" and "UNA Watch" are trademarks of UNA Watch Ltd; this project is not
affiliated with or endorsed by them.
