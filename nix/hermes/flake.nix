{
  description = "Hermes NixOS container for Proxmox LXC";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    hermes-agent.url = "github:NousResearch/hermes-agent/v2026.7.7.2";
  };

  outputs = { nixpkgs, hermes-agent, ... }: {
    nixosConfigurations.hermes = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
          hermes-agent.nixosModules.default
          ({ config, pkgs, lib, ... }:
          let
            /*
            Temporarily disabled: standalone external Hermes WebUI.
            The Hermes agent container should use its included WebUI instead.
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
            */
            remoteWebAgentToolsets = [
              "web"
            ];
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
                model = {
                  provider = "openai-api";
                  default = "gpt-5.4";
                };
                toolsets = remoteWebAgentToolsets;
                platform_toolsets = {
                  cli = remoteWebAgentToolsets;
                  api_server = remoteWebAgentToolsets;
                };
              };
            };

            /*
            Temporarily disabled: standalone external Hermes WebUI services.
            The Hermes agent container should use its included WebUI instead.
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

            systemd.services.hermes-credentials = {
              description = "Prepare Hermes WebUI credentials from shared SOPS secret";
              wantedBy = [ "multi-user.target" ];
              before = [ "hermes-webui.service" ];
              path = with pkgs; [
                coreutils
                sops
              ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu
                umask 077

                sops_secret_file="/etc/nixos/secrets/common.sops.yaml"
                sops_private_key="/etc/nixos/secrets/bootstrap-ssh-private-key"

                password="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE="$sops_private_key" sops -d --extract '["services"]["hermes"]["password"]' "$sops_secret_file" 2>/dev/null | tr -d '\n' || true)"
                [ -n "$password" ] || { echo "Missing services.hermes.password in $sops_secret_file" >&2; exit 1; }

                cat > /run/hermes-webui.env <<EOF
                HERMES_WEBUI_PASSWORD=$password
                HERMES_WEBUI_SKIP_ONBOARDING=1
                EOF
              '';
            };

            systemd.services.hermes-webui = {
              description = "Hermes WebUI";
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" "hermes-agent.service" "hermes-webui-sync.service" "hermes-credentials.service" ];
              after = [ "network-online.target" "hermes-agent.service" "hermes-webui-sync.service" "hermes-credentials.service" ];
              serviceConfig = {
                Type = "simple";
                User = "hermes";
                Group = "hermes";
                WorkingDirectory = "/appdata";
                EnvironmentFile = "/run/hermes-webui.env";
                Environment = [
                  "HOME=/appdata"
                  "HERMES_HOME=/appdata/.hermes"
                  "HERMES_WEBUI_HOST=0.0.0.0"
                  "HERMES_WEBUI_PORT=8787"
                  "HERMES_WEBUI_ALLOWED_ORIGINS=http://192.168.68.27:8787,https://hermes.home.papdavid.eu"
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
            */

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
            /*
            Temporarily disabled with the standalone external Hermes WebUI.
            environment.systemPackages = [ hermesWebuiCli ];
            */
          })
        ];
    };
  };
}
