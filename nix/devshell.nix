{ ... }:
{
  perSystem = { pkgs, config, unaSdk, unaPython, ... }:
    let
      una-build = pkgs.writeShellApplication {
        name = "una-build";
        runtimeInputs = [
          pkgs.cmake
          pkgs.gnumake
          pkgs.gcc-arm-embedded
          unaPython
        ];
        text = ''
          cmake_dir=''${1:?usage: una-build <app-CMake-dir> [version]}
          version=''${2:-0.0.0-dev}

          cmake -G "Unix Makefiles" \
            -S "$cmake_dir" -B "$cmake_dir/build" \
            -DBUILD_VERSION="$version" \
            -DUNA_PYTHON_EXECUTABLE=${unaPython}/bin/python3
          cmake --build "$cmake_dir/build"
        '';
      };
    in
    {
      devShells.default = pkgs.mkShellNoCC {
        packages = [
          pkgs.cmake
          pkgs.gnumake
          pkgs.gcc-arm-embedded
          unaPython
          una-build
          config.treefmt.build.wrapper
        ];

        UNA_SDK = unaSdk;
      };
    };
}
