{...}: {
  perSystem = {
    pkgs,
    config,
    unaSdk,
    ...
  }: {
    checks.hello-uapp = pkgs.runCommand "hello-uapp-check" {} ''
      uapp=$(find ${config.packages.hello} -name '*.uapp' | head -1)
      if [ -z "$uapp" ]; then
        echo "no .uapp produced by packages.hello"
        exit 1
      fi
      echo "found $uapp"
      touch $out
    '';

    checks.logger-uapp = pkgs.runCommand "logger-uapp-check" {} ''
      uapp=$(find ${config.packages.logger} -name '*.uapp' | head -1)
      if [ -z "$uapp" ]; then
        echo "no .uapp produced by packages.logger"
        exit 1
      fi
      echo "found $uapp"
      touch $out
    '';

    checks.host-tests = pkgs.stdenv.mkDerivation {
      name = "una-sdk-host-tests";
      src = unaSdk;

      nativeBuildInputs = [pkgs.cmake pkgs.gnumake];
      buildInputs = [pkgs.gtest];

      dontUseCmakeConfigure = true;

      buildPhase = ''
        runHook preBuild
        cmake -S Tests/Host -B build-host -DCMAKE_BUILD_TYPE=Debug
        cmake --build build-host
        runHook postBuild
      '';

      doCheck = true;
      checkPhase = ''
        runHook preCheck
        ctest --test-dir build-host --output-on-failure
        runHook postCheck
      '';

      installPhase = "touch $out";
    };
  };
}
