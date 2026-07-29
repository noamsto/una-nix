# una-nix — Nix toolchain for UNA Watch app development

**Date:** 2026-07-29
**Status:** Approved, ready for planning

## Problem

[UNAWatch/una-sdk](https://github.com/UNAWatch/una-sdk) builds apps for the UNA
Watch (STM32, Cortex-M33). Its documented setup is imperative and
platform-hostile: install STM32CubeIDE or CubeCLT behind an ST account, export
`UNA_SDK` by hand, `pip install` into a global Python, and — for GUI work — run
TouchGFX Designer on Windows. None of that survives on a Nix machine, and none
of it is reproducible.

The goal is to develop UNA Watch apps on Nix (x86_64-linux and aarch64-darwin)
with a `nix develop` shell and `nix build`-able app artifacts.

## Findings from investigation

These were established empirically against upstream at commit `69020453` and
drive most of the design decisions below.

### The ST toolchain requirement is stale for the CMake path

`Docs/sdk-setup.md` calls the ST-patched `arm-none-eabi-gcc` "CRITICAL",
warning that distro toolchains fail with missing newlib syscall stubs
(`_write`, `_close`).

That does not apply to the CMake build. `cmake/una-app.cmake` compiles and
links with `-nostdlib -nodefaultlibs -nostartfiles` against a vendored
`Libs/Source/AppSystem/Libc++/libstdc++.a`, so newlib's syscall layer is never
linked and its stubs are never needed.

**Verified:** the `Alarm` example builds end-to-end to a valid `.uapp` on
aarch64-darwin using nixpkgs `gcc-arm-embedded` 15.2.rel1, with no ST toolchain
and no Windows:

```
INFO:root:Name           : Alarm
INFO:root:ID             : A19C2A7E4F8B6D31
INFO:root:CRC            : 0xAA5DC371
INFO:root:Image          : Alarm_0.0.0-dev.uapp (210952 bytes)
```

### One upstream line blocks the build

`cmake/una-app.cmake:52` passes `-fcyclomatic-complexity`, a flag that exists
only in ST's GNU Tools for STM32 fork. Mainline ARM GCC rejects it outright:

```
arm-none-eabi-g++: error: unrecognized command-line option '-fcyclomatic-complexity'
```

Removing that single line is sufficient. Nothing else in the firmware path
required modification.

### Deployment needs no tooling

Per `Docs/deploy.md`, apps are installed by copying the `.uapp` onto the watch
over USB mass storage. There is no flasher, debug probe, or vendor upload tool
to package.

### The simulator is x86_64-linux only

`ThirdParty/touchgfx` ships prebuilt binaries with no source in the repo:

| Artifact | Format |
|---|---|
| `lib/linux/libtouchgfx.a` | x86_64 static archive, GCC 5.4 / Ubuntu 16.04 |
| `framework/tools/imageconvert/build/linux/imageconvert.out` | ELF64 dynamic executable |
| `framework/tools/fontconvert/build/linux/fontconvert.out` | ELF64 dynamic executable |
| `3rdparty/libjpeg/lib/linux/libjpeg.a` | **static** archive |

There is no macOS or aarch64 build of any of them, so the simulator cannot run
on the M4 Mac. Because the vendored libjpeg is static, the `-rpath` flag in
`una/Makefile:53` is vestigial — no shared library needs patching, and only the
two `.out` converters need `autoPatchelfHook`.

Upstream's `.github/workflows/linux-simulator.yml` builds this on ubuntu-24.04
with GCC 13 against the GCC 5.4 `libtouchgfx.a` and boots it headless under
`SDL_VIDEODRIVER=dummy`. That is good evidence there is no `_GLIBCXX_USE_CXX11_ABI`
break across the prebuilt boundary — the risk that would otherwise be the
largest threat to this layer.

Its dependency list is the reference for our `buildInputs`:
`libsdl2-dev libsdl2-image-dev libjpeg-dev ruby ruby-nokogiri`.

### TouchGFX Designer is not required to build

Designer is Windows-only, but each example commits its `generated/` output.
Designer is needed only to *edit* screen layouts, not to compile or run them.
GUI-less "Glance" apps do not involve TouchGFX at all.

### Two reproducibility traps

Both were hit during investigation and both are designed out rather than
documented around:

1. **CMake caches the absolute store path of Python.** `una-app.cmake:16` does
   `find_program(UNA_PYTHON_EXECUTABLE NAMES python3 python)` and caches the
   result. After a devShell update the cached path still exists in the store but
   no longer has `pyelftools`/`pillow`, so the build fails at the packing step
   with `ModuleNotFoundError: No module named 'elftools'` until the build
   directory is reconfigured.

2. **`una_app_setup_version` shells out to git.** It runs
   `Utilities/Scripts/build-cube/una-version.sh`, which attempts
   `git config --global safe.directory` and fails noisily outside a writable
   `HOME` or a git checkout. The function returns early when `BUILD_VERSION` is
   already defined (`una-app.cmake:79-83`), so passing it explicitly bypasses
   the script entirely.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Relationship to upstream | Own repo, `una-sdk` as `flake = false` input | The delta is one line. A 212 MB fork of a vendored-binary repo would need rebasing every release to carry it. |
| App location | Monorepo, `apps/<name>/` | One lockfile, one devShell. Apps can be extracted later if they earn it. |
| Scope | devShell + builder + simulator + host tests + upstream PR | The builder is the minimum useful unit; the rest each close a gap that would otherwise send you back to a non-Nix machine. |
| Sequencing | Simulator last | It is the only layer unverifiable from the Mac; it needs a thinkpad to validate. |
| Systems | `x86_64-linux`, `aarch64-darwin` | Matches nix-config. Simulator is linux-gated. |

## Architecture

Five layers, each independently buildable and testable.

### 1. `packages.una-sdk-src` — patched SDK tree

A derivation that realizes the upstream source with `patches/` applied.
Everything downstream sets `UNA_SDK` to this store path. The SDK is read-only
at build time; nothing writes into it.

Two patches:

- `0001-drop-fcyclomatic-complexity.patch` — removes the ST-only flag.
- `0002-host-tests-find-gtest.patch` — replaces the `FetchContent` googletest
  pull in `Tests/Host/cmake/FetchGoogleTest.cmake` with `find_package(GTest
  REQUIRED)`, since sandboxed builds have no network.

Upgrading the SDK is `nix flake update una-sdk`; patch drift surfaces as a
patch-apply failure, which is the desired loud signal.

### 2. `lib.mkUnaApp` — app directory to `.uapp`

The core abstraction and the only interface app authors touch.

```nix
mkUnaApp {
  pname = "hello";
  version = "0.1.0";
  src = ./apps/hello;
  cmakeDir = "Software/Apps/Hello-CMake";
}
```

Produces a derivation whose output contains the built `.uapp`. Internally it
sets `UNA_SDK`, and pins both trap-avoiding flags at configure time:

- `-DBUILD_VERSION=${version}` — bypasses the git-shelling version script and
  makes the version an explicit input rather than a function of ambient git
  state.
- `-DUNA_PYTHON_EXECUTABLE=${pythonEnv}/bin/python3` — pins the interpreter
  instead of letting `find_program` cache whatever is on `PATH`.

`pythonEnv` is `python3.withPackages (ps: [ ps.pyelftools ps.pillow ])`, matching
`Utilities/Scripts/app_packer/requirements.txt`.

The repo ships one seed app at `apps/hello/`, vendored from upstream's
`Examples/Apps/Alarm` (the example already proven to build) with its own
`APP_NAME` and a freshly generated `APP_ID`. Alarm was chosen because it has a
TouchGFX GUI, so it exercises the simulator layer as well as the builder — a
Glance-type app would be smaller but would not touch TouchGFX at all.

### 3. `devShells.default`

Toolchain, `pythonEnv`, and `UNA_SDK` preset, wired through direnv.

Carries a thin `una-build` wrapper that runs configure + build with the same two
pinned flags as `mkUnaApp`, so the interactive path and the derivation path
cannot drift apart.

### 4. `packages.sim-<app>` — TouchGFX simulator

Gated to `x86_64-linux` via `lib.optionalAttrs`.

- `autoPatchelfHook` over `imageconvert.out` and `fontconvert.out`.
- `buildInputs`: `SDL2`, `SDL2_image`, `ruby` + `rubyPackages.nokogiri`
  (`framework/tools/textconvert` is a Ruby script).
- Build: `make -f simulator/gcc/Makefile` with `UNA_SDK` set, per upstream CI.
- Exposed as `apps.sim-<name>` so `nix run .#sim-hello` works.

Acceptance mirrors upstream CI: the binary boots headless under
`SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy` and logs `GUI is now running`.
The simulator is a GUI loop that never exits, so success is the boot marker, not
an exit code.

### 5. `checks.host-tests`

Builds `Tests/Host` against nixpkgs `gtest` (enabled by patch 2) and runs
`ctest`, wired into `nix flake check`.

## Deliverables outside this repo

An upstream PR to `UNAWatch/una-sdk` guarding the flag:

```cmake
include(CheckCXXCompilerFlag)
check_cxx_compiler_flag(-fcyclomatic-complexity UNA_HAS_CYCLOMATIC_COMPLEXITY)
```

so ST toolchains keep the flag and mainline ARM GCC builds work unmodified. If
merged, patch 1 is deleted and the lockfile bumped. Upstream is active (last
commit 2026-07-24), MIT-licensed, and `Docs/deploy.md` explicitly invites PRs.

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Simulator unverifiable from the Mac | Medium | Sequenced last; validated on a thinkpad. Upstream CI is the reference recipe. |
| Patch 2 conflicts if upstream restructures `FetchGoogleTest.cmake` | Low | Patch-apply failure is loud, and the file is 14 lines. |
| `autoPatchelfHook` cannot satisfy GCC-5.4-era converter binaries | Low | They are ordinary dynamic ELF64; upstream runs them on Ubuntu 24.04. |
| Upstream rejects the PR | Low | No consequence — patch 1 is carried indefinitely, which is the status quo. |

## Out of scope

- TouchGFX Designer (Windows-only; `generated/` is committed, so it is not on
  the build path).
- Packaging STM32CubeCLT — account-walled, and demonstrated unnecessary.
- Watch flashing or deployment tooling — deployment is a USB file copy.
- aarch64-linux — not a system in nix-config, and the simulator binaries would
  not run there regardless.

## Success criteria

1. `nix build .#hello` produces a `.uapp` on both x86_64-linux and aarch64-darwin.
2. `nix develop` gives a working interactive build via `una-build`, with no
   manual `UNA_SDK` export and no `pip install`.
3. `nix flake check` runs the SDK host test suite green.
4. `nix run .#sim-hello` boots the simulator on x86_64-linux and logs
   `GUI is now running`.
5. A `.uapp` built through this repo runs on real hardware after a USB copy.
   Manual and hardware-gated — the only criterion that cannot be automated, and
   the only one that confirms a mainline ARM GCC build behaves like an
   ST-toolchain one rather than merely linking like one.
