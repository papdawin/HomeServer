{
  description = "Bazarr NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.bazarr = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ pkgs, ... }:
            let
              bazarrBootstrapUsername = "papdawin";
              bazarrBootstrapUserScript = builtins.readFile ./bazarr-bootstrap-user.sh;
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

              services.bazarr = {
                enable = true;
                dataDir = "/appdata";
                user = "bazarr";
                group = "media";
                listenPort = 6767;
              };
              systemd.services.bazarr.serviceConfig.UMask = "0002";

              environment.systemPackages = with pkgs; [ curl jq ];

              systemd.services.bazarr-credentials = {
                description = "Prepare Bazarr bootstrap credentials from shared SOPS secret";
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

                password="$(read_sops_secret '["services"]["bazarr"]["password"]')"
                radarr_api_key="$(read_sops_secret '["services"]["radarr"]["apiKey"]')"
                sonarr_api_key="$(read_sops_secret '["services"]["sonarr"]["apiKey"]')"
                [ -n "$password" ] || password="$(read_sops_secret '["services"]["radarr"]["password"]')"
                [ -n "$password" ] || { echo "Missing services.bazarr.password (and fallback services.radarr.password) in $sops_secret_file" >&2; exit 1; }
                [ -n "$radarr_api_key" ] || { echo "Missing services.radarr.apiKey in $sops_secret_file" >&2; exit 1; }
                [ -n "$sonarr_api_key" ] || { echo "Missing services.sonarr.apiKey in $sops_secret_file" >&2; exit 1; }

                cat > /run/bazarr-bootstrap.env <<EOF_INNER
                BAZARR_BOOTSTRAP_USERNAME=${bazarrBootstrapUsername}
                BAZARR_BOOTSTRAP_PASSWORD=$password
                BAZARR_RADARR_HOST=${radarrHost}
                BAZARR_RADARR_PORT=${toString radarrPort}
                BAZARR_RADARR_API_KEY=$radarr_api_key
                BAZARR_SONARR_HOST=${sonarrHost}
                BAZARR_SONARR_PORT=${toString sonarrPort}
                BAZARR_SONARR_API_KEY=$sonarr_api_key
                EOF_INNER
              '';
            };

              systemd.services.bazarr-bootstrap-user = {
                description = "Bootstrap Bazarr startup user";
                wantedBy = [ "multi-user.target" ];
                wants = [ "network-online.target" "bazarr.service" "bazarr-credentials.service" ];
                after = [ "network-online.target" "bazarr.service" "bazarr-credentials.service" ];
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
                script = bazarrBootstrapUserScript;
              };

              services.openssh = {
                enable = true;
                settings = {
                  PasswordAuthentication = true;
                  PermitRootLogin = "yes";
                };
              };

              networking.firewall.allowPing = true;
              networking.firewall.allowedTCPPorts = [ 22 6767 ];
            })
        ];
    };
  };
}
