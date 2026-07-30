# TouchGFX simulator package (x86_64-linux only — vendored TouchGFX binaries
# are prebuilt x86_64 ELF/static-archive artifacts, no aarch64 equivalents
# exist). UNTESTED: this derivation cannot be built or run on aarch64-darwin,
# so it has only been verified by `nix eval`, never by an actual build.
#
# The platform gate lives on the individual `packages`/`apps` attrs (not
# wrapped around the whole perSystem return) because gating the entire
# return with `lib.optionalAttrs (system == ...) { ... }` defeats
# flake-parts' static "is formatter defined for every system" heuristic and
# breaks `nix flake show` for aarch64-darwin.
{ ... }:
{
  perSystem = { pkgs, lib, system, config, unaSdk, ... }: {
    packages = lib.optionalAttrs (system == "x86_64-linux") {
      sim-hello = pkgs.stdenv.mkDerivation {
        pname = "sim-hello";
        version = "0.1.0";
        src = ../apps/hello;

        nativeBuildInputs = [
          pkgs.gnumake
          pkgs.autoPatchelfHook
          pkgs.ruby
          pkgs.rubyPackages.nokogiri
        ];

        buildInputs = [
          pkgs.SDL2
          pkgs.SDL2_image
          pkgs.libjpeg
          pkgs.stdenv.cc.cc.lib
        ];

        UNA_SDK = unaSdk;

        # una/Makefile's config/gcc/app.mk hardcodes touchgfx_path as a
        # relative offset (../../../../../../ThirdParty/touchgfx) that
        # assumes the app lives inside the SDK checkout at a fixed depth
        # (Examples/Apps/<App>/Software/Apps/TouchGFX-GUI). Our app tree
        # doesn't nest that way, so touchgfx_path is overridden on the make
        # command line to point at $UNA_SDK directly — touchgfx_path is a
        # plain `:=` in the makefile, not `override`, so a command-line
        # assignment wins and propagates to the `una/Makefile` sub-make.
        #
        # imageconvert.out and fontconvert.out are dynamically linked ELF
        # executables vendored in the (read-only) SDK store path, and they
        # run *during* the build (via the Makefile's `assets` target), so
        # autoPatchelfHook's normal postFixup pass — which only patches
        # $out — can't reach them in time. They're copied to a writable
        # directory and patched explicitly before `make` runs, then pointed
        # at via the same command-line-override mechanism as touchgfx_path.
        buildPhase = ''
          runHook preBuild

          patchedTools=$PWD/patched-tools
          mkdir -p "$patchedTools"
          cp ${unaSdk}/ThirdParty/touchgfx/framework/tools/imageconvert/build/linux/imageconvert.out "$patchedTools/"
          cp ${unaSdk}/ThirdParty/touchgfx/framework/tools/fontconvert/build/linux/fontconvert.out "$patchedTools/"
          chmod +w "$patchedTools"/*.out
          autoPatchelf "$patchedTools"

          cd Software/Apps/TouchGFX-GUI
          make -f simulator/gcc/Makefile -j$NIX_BUILD_CORES \
            touchgfx_path=${unaSdk}/ThirdParty/touchgfx \
            imageconvert_executable=$patchedTools/imageconvert.out \
            fontconvert_executable=$patchedTools/fontconvert.out

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          cp build/bin/simulator.out $out/bin/sim-hello
          runHook postInstall
        '';
      };
    };

    apps = lib.optionalAttrs (system == "x86_64-linux") {
      sim-hello = {
        type = "app";
        program = "${config.packages.sim-hello}/bin/sim-hello";
      };
    };
  };
}
