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

  configPath = config.constructFiles.generatedConfig.path;
in
{
  imports = [ wlib.modules.default ];

  config.meta.description = ''
    Wrapper module for [Umbriel](https://docs.noctalia.dev/umbriel/), a Wayland compositor built on wlroots.

    `settings` may be a Nix attribute set (translated to TOML), a raw TOML string, or a path to a TOML file.

    The generated config is passed via `-c`, but only when umbriel is started as a compositor
    (no arguments, or a leading `-s`). Subcommands such as `umbriel msg ...` are passed through untouched,
    because umbriel does not accept `-c` in front of a subcommand.

    The systemd unit and session files shipped by the package are patched to point at the wrapper.

    `[include]` paths in a generated config resolve relative to the generated file in the nix store.
    Use absolute paths for includes that live outside of the store.
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
          general.autostart = [ "noctalia" ];
          layout.gap = 5;
          input.keyboard.layout = "se";
          keybinds."Mod+X" = "window-close";
        }
      '';
      description = ''
        Umbriel configuration. May be a Nix attribute set (translated to TOML),
        a string of raw TOML, or a path to a `.toml` file.

        See <https://docs.noctalia.dev/umbriel/configuration/>.

        When empty, no `-c` flag is added and umbriel reads `$XDG_CONFIG_HOME/umbriel/config.toml`.

        An absolute path string outside the nix store is passed as is,
        and requires `disableConfigValidation = true`.
      '';
    };
    disableConfigValidation = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When `false`, the build runs `umbriel config validate -c <config>` and fails if it reports anything.

        Disabled by default: validation exits non-zero on warnings as well as errors,
        and the upstream home-manager module dropped its build-time check.
      '';
    };
  };

  config.package = lib.mkDefault pkgs.umbriel;

  config.filesToPatch = [
    "share/applications/*.desktop"
    "share/wayland-sessions/*.desktop"
    "lib/systemd/user/umbriel.service"
    "share/systemd/user/umbriel.service"
    "bin/start-umbriel"
  ];

  config.constructFiles.generatedConfig = lib.mkIf hasSettings {
    relPath = "${config.binName}-config.toml";
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

  config.runShell = lib.mkIf hasSettings [
    {
      name = "UMBRIEL_CONFIG_FLAG";
      data = ''
        if [ "$#" -eq 0 ] || [ "$1" = "-s" ]; then
          set -- -c ${lib.escapeShellArg configPath} "$@"
        fi
      '';
    }
  ];

  config.drv.installPhase = lib.mkIf (hasSettings && !config.disableConfigValidation) ''
    runHook preInstall
    ${lib.getExe config.package} config validate -c ${configPath}
    runHook postInstall
  '';

  config.passthru.providedSessions = config.package.passthru.providedSessions or [ "umbriel" ];

  config.meta.maintainers = [ wlib.maintainers.WinterMaximus ]; # TODO: your own entry
  config.meta.platforms = lib.platforms.linux;
}
