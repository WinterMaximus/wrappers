{
  pkgs,
  self,
  tlib,
  ...
}:
let
  inherit (tlib)
    isFile
    notIsFile
    fileContains
    notFileContains
    test
    ;

  # validation is enabled by default, so this also exercises `noctalia config validate` at build time
  wrapper = self.wrappers.noctalia.wrap {
    inherit pkgs;
    settings = {
      theme.mode = "dark";
      bar.default.position = "top";
    };
  };

  # settings given as a path to an existing TOML file
  pathWrapper = self.wrappers.noctalia.wrap {
    inherit pkgs;
    settings = pkgs.writeText "noctalia-path.toml" ''
      [theme]
      mode = "light"
    '';
  };

  # settings given as raw TOML
  textWrapper = self.wrappers.noctalia.wrap {
    inherit pkgs;
    settings = ''
      [bar.default]
      position = "bottom"
    '';
  };

  emptyWrapper = self.wrappers.noctalia.wrap { inherit pkgs; };

  script = "${wrapper}/bin/noctalia";
  configFile = "${wrapper}/noctalia-config/noctalia/config.toml";
in
test { wrapper = "noctalia"; } {
  "noctalia wrapper binary should exist" = [ (isFile script) ];

  "noctalia wrapper should point NOCTALIA_CONFIG_HOME at the generated directory" = [
    (fileContains script "NOCTALIA_CONFIG_HOME")
    (fileContains script "noctalia-config")
  ];

  "noctalia attrset settings should be translated to TOML" = [
    (isFile configFile)
    (fileContains configFile "^\\[theme\\]")
    (fileContains configFile "mode = \"dark\"")
    (fileContains configFile "position = \"top\"")
  ];

  "noctalia path settings should be copied as is" = [
    (fileContains "${pathWrapper}/noctalia-config/noctalia/config.toml" "mode = \"light\"")
  ];

  "noctalia raw string settings should be written as is" = [
    (fileContains "${textWrapper}/noctalia-config/noctalia/config.toml" "position = \"bottom\"")
  ];

  "noctalia with empty settings should not override the config directory" = [
    (notIsFile "${emptyWrapper}/noctalia-config/noctalia/config.toml")
    (notFileContains "${emptyWrapper}/bin/noctalia" "NOCTALIA_CONFIG_HOME")
  ];
}
