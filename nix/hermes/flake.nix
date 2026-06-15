{
  description = "Hermes NixOS container for Proxmox LXC";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    hermes-agent.url = "github:NousResearch/hermes-agent";
  };

  outputs = { nixpkgs, hermes-agent, ... }: {
    nixosConfigurations.hermes = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          hermes-agent.nixosModules.default
          ({ config, pkgs, lib, ... }:
          let
            hermesWebuiStart = pkgs.writeShellScript "hermes-webui-start" ''
              set -euo pipefail

              export HERMES_WEBUI_PYTHON="$(
                awk -F"'" '/^export HERMES_PYTHON=/{ print $2; exit }' \
                  "${config.services.hermes-agent.package}/bin/hermes"
              )"
              exec ${pkgs.python3}/bin/python3 /appdata/hermes-webui/bootstrap.py --foreground --no-browser --host 0.0.0.0 8787
            '';
            hermesWebuiCli = pkgs.writeShellScriptBin "hermes-webui-cli" ''
              set -euo pipefail

              if [ "$(id -u)" -eq 0 ]; then
                exec ${pkgs.sudo}/bin/sudo -u hermes \
                  HOME=/appdata \
                  HERMES_HOME=/appdata/.hermes \
                  ${config.services.hermes-agent.package}/bin/hermes "$@"
              fi

              export HOME=/appdata
              export HERMES_HOME=/appdata/.hermes
              exec ${config.services.hermes-agent.package}/bin/hermes "$@"
            '';
          in {
            system.stateVersion = "25.11";
            boot.isContainer = true;
            boot.tmp.useTmpfs = false;

            systemd.mounts = [
              {
                enable = false;
                where = "/sys/kernel/debug";
              }
            ];

            users.mutableUsers = false;
            users.groups.media = {
              gid = 2000;
            };
            users.users.papdawin = {
              isNormalUser = true;
              extraGroups = [
                "wheel"
                "media"
              ];
              hashedPasswordFile = "/etc/nixos/secrets/papdawin-password-hash";
            };
            users.users.hermes.shell = lib.mkForce pkgs.bashInteractive;

            services.hermes-agent = {
              enable = true;
              stateDir = "/appdata";
              addToSystemPackages = true;
              extraPackages = [ pkgs.honcho ];
              extraDependencyGroups = [ "honcho" ];
              settings = {
                model.default = "anthropic/claude-sonnet-4";
                toolsets = [ "all" ];
                platform_toolsets = {
                  cli = [
                    "all"
                    "moa"
                    "homeassistant"
                    "spotify"
                    "video"
                    "video_gen"
                    "x_search"
                  ];
                  api_server = [
                    "all"
                    "moa"
                    "homeassistant"
                    "spotify"
                    "video"
                    "video_gen"
                    "x_search"
                  ];
                };
              };
            };

            systemd.services.hermes-webui-sync = {
              description = "Sync Hermes WebUI source";
              wantedBy = [ "multi-user.target" ];
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              path = with pkgs; [
                git
                coreutils
              ];
              serviceConfig = {
                Type = "oneshot";
                User = "hermes";
                Group = "hermes";
                WorkingDirectory = "/appdata";
              };
              script = ''
                set -eu
                repo_dir="/appdata/hermes-webui"
                if [ ! -d "$repo_dir/.git" ]; then
                  rm -rf "$repo_dir"
                  git clone --depth 1 https://github.com/nesquena/hermes-webui.git "$repo_dir"
                else
                  git -C "$repo_dir" fetch --depth 1 origin master
                  git -C "$repo_dir" reset --hard origin/master
                fi
              '';
            };

            systemd.services.hermes-webui = {
              description = "Hermes WebUI";
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" "hermes-agent.service" "hermes-webui-sync.service" ];
              after = [ "network-online.target" "hermes-agent.service" "hermes-webui-sync.service" ];
              serviceConfig = {
                Type = "simple";
                User = "hermes";
                Group = "hermes";
                WorkingDirectory = "/appdata";
                Environment = [
                  "HOME=/appdata"
                  "HERMES_HOME=/appdata/.hermes"
                  "HERMES_WEBUI_HOST=0.0.0.0"
                  "HERMES_WEBUI_PORT=8787"
                  "HERMES_WEBUI_ALLOWED_ORIGINS=http://192.168.68.27:8787,https://hermes.home.papdavid.eu"
                  "HERMES_WEBUI_ONBOARDING_OPEN=1"
                  "HERMES_WEBUI_STATE_DIR=/appdata/.hermes/webui"
                  "PATH=/run/current-system/sw/bin:/usr/bin:/bin"
                ];
                ExecStart = hermesWebuiStart;
                Restart = "always";
                RestartSec = 5;
              };
              path = with pkgs; [
                git
                python3
                gawk
                bash
                coreutils
              ];
            };

            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = true;
                PermitRootLogin = "yes";
              };
            };

            networking.firewall.allowPing = true;
            networking.firewall.allowedTCPPorts = [ 22 ];
            networking.firewall.extraCommands = ''
              iptables -A nixos-fw -p tcp -s 192.168.68.38 --dport 8787 -j nixos-fw-accept
            '';
            environment.systemPackages = [ hermesWebuiCli ];
          })
        ];
    };
  };
}
