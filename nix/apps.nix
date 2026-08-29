{...}: {
  perSystem = {mkUnaApp, ...}: {
    packages.hello = mkUnaApp {
      pname = "hello";
      version = "0.1.0";
      src = ../apps/hello;
      cmakeDir = "Software/Apps/Hello-CMake";
    };

    packages.logger = mkUnaApp {
      pname = "logger";
      version = "0.1.0";
      src = ../apps/logger;
      cmakeDir = "Software/Apps/Logger-CMake";
    };
  };
}
