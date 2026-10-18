{
  config,
  lib,
  wlib,
  pkgs,
  ...
}:
let
  kind =
    let
      s = config.settings;
    in
    if builtins.isAttrs s && !(s ? outPath || s ? __toString) then
      "attrs"
    else if builtins.isString s && !wlib.types.linkable.check s then
      "text"
    else
      "path";

  hasSettings =
    if kind == "attrs" then
      config.settings != { }
    else if kind == "text" then
      config.settings != ""
    else
      true;

  configHomeDirname = "${config.binName}-config";
  configHome = "${placeholder config.outputName}/${configHomeDirname}";
in
{
  imports = [ wlib.modules.default ];

  config.meta.description = ''
    Wrapper module for [Noctalia v5](https://docs.noctalia.dev/noctalia/), the native Wayland desktop shell.
    This is NOT for the Quickshell based v4 line, see `wrappers.noctalia-shell` for that.

    `settings` may be a Nix attribute set (translated to TOML), a raw TOML string, or a path to a TOML file.

    `NOCTALIA_CONFIG_HOME` is pointed at a generated directory in the wrapper. This replaces
    `~/.config/noctalia/` as the hand-written layer, while GUI overrides in
    `~/.local/state/noctalia/settings.toml` are still read and still win.
  '';

  options = {
    settings = lib.mkOption {
      type = lib.types.oneOf [
        wlib.types.linkable
        lib.types.lines
        (lib.types.attrsOf (
          wlib.types.structuredValueWith {
            typeName = "TOML";
            nullable = false;
          }
        ))
      ];
      default = { };
      example = lib.literalExpression ''
        {
          theme = {
            mode = "dark";
            source = "builtin";
            builtin = "Catppuccin";
          };
        }
      '';
      description = ''
        Noctalia configuration. May be a Nix attribute set (translated to TOML),
        a string of raw TOML, or a path to a `.toml` file such as `./noctalia.toml`.

        The file is copied into the wrapper at build time, so a path must be one nix can read.

        See <https://docs.noctalia.dev/noctalia/configuration/>.

        When empty, `NOCTALIA_CONFIG_HOME` is not set.
      '';
    };
    disableConfigValidation = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When `true`, the build will not run `noctalia config validate` on the config.
        Only errors fail the build; unknown keys are warnings.
      '';
    };
  };

  config.package = lib.mkDefault pkgs.noctalia;

  config.constructFiles.generatedConfig = lib.mkIf hasSettings {
    relPath = "${configHomeDirname}/noctalia/config.toml";
    content =
      if kind == "attrs" then
        builtins.toJSON config.settings
      else if kind == "text" then
        config.settings
      else
        "";
    builder =
      if kind == "attrs" then
        ''${pkgs.remarshal}/bin/json2toml "$1" "$2"''
      else if kind == "path" then
        ''cp ${lib.escapeShellArg "${config.settings}"} "$2"''
      else
        ''cp "$1" "$2"'';
  };

  config.env.NOCTALIA_CONFIG_HOME = lib.mkIf hasSettings configHome;

  config.drv.installPhase = lib.mkIf (hasSettings && !config.disableConfigValidation) ''
    runHook preInstall
    ${lib.getExe config.package} config validate ${config.constructFiles.generatedConfig.path}
    runHook postInstall
  '';

  config.meta.maintainers = [ wlib.maintainers.WinterMaximus ]; # TODO: your own entry
  config.meta.platforms = lib.platforms.linux;
}
