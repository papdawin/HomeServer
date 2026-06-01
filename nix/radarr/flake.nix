{
  description = "Radarr NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.radarr = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ pkgs, ... }:
            let
              radarrBootstrapUsername = "papdawin";
              radarrBootstrapUserScript = builtins.readFile ./radarr-bootstrap-user.sh;
              qbittorrentHost = "192.168.68.26";
              qbittorrentPort = 8080;
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

              services.radarr = {
                enable = true;
                dataDir = "/appdata";
                user = "radarr";
                group = "media";
                settings.server = {
                  bindaddress = "*";
                  port = 7878;
                };
              };
              systemd.services.radarr.serviceConfig.UMask = "0002";

              environment.systemPackages = with pkgs; [ curl jq ];

              systemd.services.radarr-credentials = {
                description = "Prepare Radarr bootstrap credentials from shared SOPS secret";
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

                  qbt_username="$(read_sops_secret '["services"]["qbittorrent"]["username"]')"
                  [ -n "$qbt_username" ] || qbt_username="${radarrBootstrapUsername}"
                  qbt_password="$(read_sops_secret '["services"]["qbittorrent"]["password"]')"
                  password="$(read_sops_secret '["services"]["radarr"]["password"]')"
                  api_key="$(read_sops_secret '["services"]["radarr"]["apiKey"]')"

                  [ -n "$qbt_password" ] || { echo "Missing services.qbittorrent.password in $sops_secret_file" >&2; exit 1; }
                  [ -n "$password" ] || { echo "Missing services.radarr.password in $sops_secret_file" >&2; exit 1; }
                  [ -n "$api_key" ] || { echo "Missing services.radarr.apiKey in $sops_secret_file" >&2; exit 1; }

                  cat > /run/radarr-bootstrap.env <<EOF_INNER
                  RADARR_QBITTORRENT_HOST=${qbittorrentHost}
                  RADARR_QBITTORRENT_PORT=${toString qbittorrentPort}
                  RADARR_QBITTORRENT_USERNAME=$qbt_username
                  RADARR_QBITTORRENT_PASSWORD=$qbt_password
                  RADARR_API_KEY=$api_key
                  RADARR_BOOTSTRAP_USERNAME=${radarrBootstrapUsername}
                  RADARR_BOOTSTRAP_PASSWORD=$password
                  EOF_INNER
                '';
              };

              systemd.services.radarr-bootstrap-user = {
                description = "Bootstrap Radarr startup user";
                wantedBy = [ "multi-user.target" ];
                wants = [ "network-online.target" "radarr.service" "radarr-credentials.service" ];
                after = [ "network-online.target" "radarr.service" "radarr-credentials.service" ];
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
                script = radarrBootstrapUserScript;
              };

              services.openssh = {
                enable = true;
                settings = {
                  PasswordAuthentication = true;
                  PermitRootLogin = "yes";
                };
              };

              networking.firewall.allowPing = true;
              networking.firewall.allowedTCPPorts = [ 22 7878 ];
            })
        ];
    };
  };
}
