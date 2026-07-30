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
