{ ... }:
{
  perSystem = { pkgs, config, ... }: {
    checks.hello-uapp = pkgs.runCommand "hello-uapp-check" { } ''
      uapp=$(find ${config.packages.hello} -name '*.uapp' | head -1)
      if [ -z "$uapp" ]; then
        echo "no .uapp produced by packages.hello"
        exit 1
      fi
      echo "found $uapp"
      touch $out
    '';
  };
}
