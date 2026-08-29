{...}: {
  perSystem = {mkUnaApp, ...}: {
    packages.hello = mkUnaApp {
      pname = "hello";
      version = "0.1.0";
      src = ../apps/hello;
      cmakeDir = "Software/Apps/Hello-CMake";
    };
  };
}
