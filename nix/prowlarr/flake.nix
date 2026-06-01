{
  description = "Prowlarr NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.prowlarr = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ lib, pkgs, ... }:
            let
              prowlarrBootstrapUsername = "papdawin";
              prowlarrBootstrapUserScript = builtins.readFile ./prowlarr-bootstrap-user.sh;
              prowlarrUrl = "http://192.168.68.31:9696";
              radarrHost = "192.168.68.29";
              radarrPort = 7878;
              sonarrHost = "192.168.68.30";
              sonarrPort = 8989;
            in {
            system.stateVersion = "25.11";
            boot.isContainer = true;

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
            users.users.prowlarr = {
              isSystemUser = true;
              group = "media";
              home = "/appdata";
            };

            services.prowlarr = {
              enable = true;
              settings.server = {
                bindaddress = "*";
                port = 9696;
              };
            };

            systemd.services.prowlarr.serviceConfig = {
              DynamicUser = lib.mkForce false;
              User = "prowlarr";
              Group = "media";
              StateDirectory = lib.mkForce "";
              ExecStart = lib.mkForce "${lib.getExe pkgs.prowlarr} -nobrowser -data=/appdata";
              UMask = "0002";
            };
            systemd.services.prowlarr.environment.HOME = lib.mkForce "/appdata";

            environment.systemPackages = with pkgs; [ curl jq ];

            systemd.services.prowlarr-credentials = {
              description = "Prepare Prowlarr bootstrap credentials from shared SOPS secret";
              wantedBy = [ "multi-user.target" ];
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

                read_sops_secret() {
                  local extract="$1"
                  SOPS_AGE_SSH_PRIVATE_KEY_FILE="$sops_private_key" sops -d --extract "$extract" "$sops_secret_file" 2>/dev/null | tr -d '\n' || true
                }

                password="$(read_sops_secret '["services"]["prowlarr"]["password"]')"
                ncore_username="$(read_sops_secret '["services"]["ncore"]["username"]')"
                [ -n "$ncore_username" ] || ncore_username="$(read_sops_secret '["services"]["prowlarr"]["ncore"]["username"]')"
                ncore_password="$(read_sops_secret '["services"]["ncore"]["password"]')"
                [ -n "$ncore_password" ] || ncore_password="$(read_sops_secret '["services"]["prowlarr"]["ncore"]["password"]')"
                radarr_api_key="$(read_sops_secret '["services"]["radarr"]["apiKey"]')"
                sonarr_api_key="$(read_sops_secret '["services"]["sonarr"]["apiKey"]')"

                [ -n "$password" ] || { echo "Missing services.prowlarr.password in $sops_secret_file" >&2; exit 1; }
                [ -n "$radarr_api_key" ] || { echo "Missing services.radarr.apiKey in $sops_secret_file" >&2; exit 1; }
                [ -n "$sonarr_api_key" ] || { echo "Missing services.sonarr.apiKey in $sops_secret_file" >&2; exit 1; }

                cat > /run/prowlarr-bootstrap.env <<EOF
                PROWLARR_BOOTSTRAP_USERNAME=${prowlarrBootstrapUsername}
                PROWLARR_BOOTSTRAP_PASSWORD=$password
                PROWLARR_NCORE_USERNAME=$ncore_username
                PROWLARR_NCORE_PASSWORD=$ncore_password
                PROWLARR_URL=${prowlarrUrl}
                PROWLARR_RADARR_HOST=${radarrHost}
                PROWLARR_RADARR_PORT=${toString radarrPort}
                PROWLARR_RADARR_API_KEY=$radarr_api_key
                PROWLARR_SONARR_HOST=${sonarrHost}
                PROWLARR_SONARR_PORT=${toString sonarrPort}
                PROWLARR_SONARR_API_KEY=$sonarr_api_key
                EOF
              '';
            };

            systemd.services.prowlarr-bootstrap-user = {
              description = "Bootstrap Prowlarr startup user";
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" "prowlarr.service" "prowlarr-credentials.service" ];
              after = [ "network-online.target" "prowlarr.service" "prowlarr-credentials.service" ];
              path = with pkgs; [
                bash
                coreutils
                curl
                jq
                gnused
                systemd
              ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = prowlarrBootstrapUserScript;
            };

            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = true;
                PermitRootLogin = "yes";
              };
            };

            networking.firewall.allowPing = true;
            networking.firewall.allowedTCPPorts = [ 22 9696 ];
          })
        ];
    };
  };
}
