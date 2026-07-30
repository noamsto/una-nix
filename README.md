# una-nix

Build [UNA Watch](https://unawatch.com) apps with Nix — on Linux or macOS, with
no STM32CubeIDE, no ST account, and no Windows.

```bash
nix develop            # toolchain + UNA_SDK, ready to go
nix build .#hello      # -> result/Hello_0.1.0.uapp
```

Copy the `.uapp` onto the watch over USB and you're done.

## What works where

| | x86_64-linux | aarch64-darwin |
|---|---|---|
| Build apps to `.uapp` | ✅ | ✅ |
| devShell + `una-build` | ✅ | ✅ |
| SDK host unit tests | ✅ | ✅ |
| TouchGFX simulator | ⚠️ untested | ❌ not possible |

The simulator is x86_64-linux only: the TouchGFX artifacts it needs
(`libtouchgfx.a`, `imageconvert.out`, `fontconvert.out`) ship as prebuilt x86_64
ELF with no macOS or aarch64 equivalent. On Apple Silicon you get the firmware
path, which is the part that matters for shipping.

**Honest status:** the firmware path is verified end-to-end and produces a valid
`.uapp`. The simulator derivation has never actually been built — it is verified
only by Nix evaluation, which catches expression errors but not link or runtime
failures. No `.uapp` from this repo has yet been run on real hardware.

## Requirements

Nix with flakes enabled. That's all — no SDK checkout, no `pip install`, no
`UNA_SDK` to export. The SDK is a pinned flake input, patched and realized into
the store.

## Why this exists

The SDK's setup guide calls the ST-patched `arm-none-eabi-gcc` from
STM32CubeIDE/CubeCLT **"CRITICAL"**, warning that other toolchains fail with
missing newlib syscall stubs (`_write`, `_close`).

That warning does not apply to the CMake build path. `cmake/una-app.cmake`
compiles and links with `-nostdlib -nodefaultlibs -nostartfiles` against a
vendored `libstdc++.a`, so newlib's syscall layer is never linked and its stubs
are never needed. Stock nixpkgs `gcc-arm-embedded` builds a valid package.

Exactly one line stood in the way: `una-app.cmake` passes
`-fcyclomatic-complexity`, which exists only in ST's GNU Tools for STM32 fork.
`patches/0001` makes it opt-in. That fix is filed upstream as
[una-sdk#232](https://github.com/UNAWatch/una-sdk/pull/232); if it merges, the
patch goes away.

## Usage

### Build an app

```bash
nix build .#hello
ls result/            # Hello_0.1.0.uapp
```

### Iterate interactively

Inside `nix develop`:

```bash
una-build apps/hello/Software/Apps/Hello-CMake 0.1.0
```

`una-build` wraps CMake with the two flags that keep interactive and sandboxed
builds identical. Both matter — see [Gotchas](#gotchas).

### Run the simulator

```bash
nix run .#sim-hello      # x86_64-linux only
```

### Run the SDK's tests

```bash
nix flake check
```

Runs UNA's own GoogleTest suite. `patches/0002` swaps its `FetchContent`
googletest pull for `find_package(GTest)`, since sandboxed builds have no
network.

## Deploying to the watch

No flasher, no debug probe — deployment is a file copy:

1. Connect over USB and wait for mass storage to appear. It may take a moment;
   running apps flush their data first.
2. Create `Apps/<AppName>/` on the watch volume.
3. Copy the `.uapp` into it.
4. Eject safely, disconnect, power-cycle the watch.
5. Press the top-right button to find your app.

`.uapp` packages carry a CRC, not a signature, so sideloading needs no developer
account.

## Adding an app

1. `cp -r apps/hello apps/myapp`
2. Rename `Software/Apps/Hello-CMake` to `Software/Apps/MyApp-CMake`.
3. In its `CMakeLists.txt`, set `APP_NAME`, `APP_USER_NAME`, and a unique
   `APP_ID` (16 uppercase hex chars):
   ```bash
   python3 -c 'import hashlib; print(hashlib.md5(b"MyApp").hexdigest().upper()[:16])'
   ```
   Take one from the [developer portal](https://apps.unawatch.com) instead if
   you intend to publish.
4. Register it in `nix/apps.nix`:
   ```nix
   packages.myapp = mkUnaApp {
     pname = "myapp";
     version = "0.1.0";
     src = ../apps/myapp;
     cmakeDir = "Software/Apps/MyApp-CMake";
   };
   ```

Editing screen layouts still needs TouchGFX Designer, which is Windows-only.
*Building* does not — each app commits its `generated/` output, so the GUI
compiles and runs from a checkout alone. Glance-type apps skip TouchGFX
entirely.

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

Upgrade the SDK with `nix flake update una-sdk`. Patch drift surfaces as a
patch-apply failure, which is the signal you want.

## Gotchas

Three sharp edges, all designed around rather than documented at. They explain
why the code looks the way it does.

**CMake caches Python's store path.** `una-app.cmake` runs
`find_program(UNA_PYTHON_EXECUTABLE ...)` and caches the result. After a devShell
update that path still exists but no longer carries `pyelftools`/`pillow`, and
the build dies at packing with `ModuleNotFoundError: No module named 'elftools'`
until you reconfigure. Both `mkUnaApp` and `una-build` pin the interpreter.

**The version script shells out to git.** `una_app_setup_version` invokes
`una-version.sh`, which runs `git config --global safe.directory` and fails
outside a writable `HOME`. It returns early when `BUILD_VERSION` is already
defined, so both paths pass it explicitly.

**TouchGFX assumes apps live inside the SDK tree.** `config/gcc/app.mk` hardcodes
`touchgfx_path := ../../../../../../ThirdParty/touchgfx` — a six-level relative
offset that only resolves for apps at
`<sdk>/Examples/Apps/<App>/Software/Apps/TouchGFX-GUI`. Out-of-tree apps, which
is the entire point of this repo, must override it on the make command line.
`nix/simulator.nix` does.

## License

The Nix code in this repository is MIT — see [`LICENSE`](LICENSE).

`apps/hello/` is a rebranded copy of the SDK's `Examples/Apps/Alarm`, which is
UNA Watch Ltd's code redistributed under its upstream MIT terms — see
[`apps/hello/LICENSE`](apps/hello/LICENSE).

The TouchGFX framework is **not** vendored here. It is fetched from the SDK at
build time and licensed separately under STMicroelectronics SLA0048, which
permits use only in connection with ST microcontrollers. If you redistribute
build outputs, read
[the SDK's third-party terms](https://github.com/UNAWatch/una-sdk/blob/main/THIRD-PARTY-LICENSES.md)
first.

"UNA" and "UNA Watch" are trademarks of UNA Watch Ltd. This is an unofficial
community project, not affiliated with or endorsed by them.
