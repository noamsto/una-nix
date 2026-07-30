{ ... }:
{
  perSystem = { pkgs, unaSdk, unaPython, ... }: {
    _module.args.mkUnaApp =
      { pname, version, src, cmakeDir }:
      pkgs.stdenvNoCC.mkDerivation {
        inherit pname version src;

        nativeBuildInputs = [
          pkgs.cmake
          pkgs.gnumake
          pkgs.gcc-arm-embedded
          unaPython
        ];

        # The SDK ships its own ARM toolchain file and drives configure itself;
        # nixpkgs' cmake hook would configure the wrong directory.
        dontUseCmakeConfigure = true;

        # The output is a packaged ARM firmware container, not a host binary —
        # there is nothing to strip or patchelf, and the reference scanner
        # segfaults walking it.
        dontFixup = true;

        UNA_SDK = unaSdk;

        buildPhase = ''
          runHook preBuild
          cmake -G "Unix Makefiles" \
            -S ${cmakeDir} -B build \
            -DBUILD_VERSION=${version} \
            -DUNA_PYTHON_EXECUTABLE=${unaPython}/bin/python3
          cmake --build build
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          find . -name '*.uapp' -exec cp {} $out/ \;
          runHook postInstall
        '';
      };
  };
}
