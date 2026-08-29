{ inputs, ... }:
{
  perSystem = { pkgs, ... }:
    let
      unaSdk = pkgs.stdenvNoCC.mkDerivation {
        pname = "una-sdk-src";
        version = inputs.una-sdk.shortRev or "dirty";
        src = inputs.una-sdk;

        patches = [
          ../patches/0002-host-tests-find-gtest.patch
        ];

        dontConfigure = true;
        dontBuild = true;
        dontFixup = true;

        installPhase = ''
          runHook preInstall
          cp -r . $out
          runHook postInstall
        '';
      };
    in
    {
      _module.args.unaPython = pkgs.python3.withPackages (ps: [
        ps.pyelftools
        ps.pillow
      ]);
      _module.args.unaSdk = unaSdk;

      packages.una-sdk-src = unaSdk;
    };
}
