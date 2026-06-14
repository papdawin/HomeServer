{
  description = "Lidarr NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.lidarr = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ pkgs, ... }:
            let
              lidarrBootstrapUsername = "papdawin";
              lidarrBootstrapUserScript = builtins.readFile ./lidarr-bootstrap-user.sh;
              lidarrNightly = pkgs.lidarr.overrideAttrs (_oldAttrs: rec {
                version = "3.1.3.4970";
                src = pkgs.fetchurl {
                  url = "https://dev.azure.com/Lidarr/Lidarr/_apis/build/builds/4931/artifacts?artifactName=Packages&fileId=7AD8D19092003AC6380BF5A6101E7221DDDFBB6F788276125BAA4010C589F27E02&fileName=Lidarr.develop.${version}.linux-core-x64.tar.gz&api-version=5.1";
                  hash = "sha256-XWIJYFvxcaAT34/R/DINyFn5bDpjW4bD/ca9jtcEKRc=";
                };
              });
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

              services.lidarr = {
                enable = true;
                package = lidarrNightly;
                dataDir = "/appdata/lidarr";
                user = "lidarr";
                group = "media";
                settings.server = {
                  bindaddress = "*";
                  port = 8686;
                };
              };
              systemd.services.lidarr.serviceConfig.UMask = "0002";
              systemd.tmpfiles.rules = [
                "d /media/music 2775 root media - -"
                "d /media/downloads 2775 root media - -"
                "d /media/downloads/lidarr 2775 root media - -"
              ];

              environment.systemPackages = with pkgs; [ curl jq ];

              systemd.services.lidarr-credentials = {
                description = "Prepare Lidarr bootstrap credentials from shared SOPS secret";
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
                  [ -n "$qbt_username" ] || qbt_username="${lidarrBootstrapUsername}"
                  qbt_password="$(read_sops_secret '["services"]["qbittorrent"]["password"]')"
                  password="$(read_sops_secret '["services"]["lidarr"]["password"]')"
                  api_key="$(read_sops_secret '["services"]["lidarr"]["apiKey"]')"

                  [ -n "$qbt_password" ] || { echo "Missing services.qbittorrent.password in $sops_secret_file" >&2; exit 1; }
                  [ -n "$password" ] || { echo "Missing services.lidarr.password in $sops_secret_file" >&2; exit 1; }
                  [ -n "$api_key" ] || { echo "Missing services.lidarr.apiKey in $sops_secret_file" >&2; exit 1; }

                  cat > /run/lidarr-bootstrap.env <<EOF_INNER
                  LIDARR_QBITTORRENT_HOST=${qbittorrentHost}
                  LIDARR_QBITTORRENT_PORT=${toString qbittorrentPort}
                  LIDARR_QBITTORRENT_USERNAME=$qbt_username
                  LIDARR_QBITTORRENT_PASSWORD=$qbt_password
                  LIDARR_API_KEY=$api_key
                  LIDARR_BOOTSTRAP_USERNAME=${lidarrBootstrapUsername}
                  LIDARR_BOOTSTRAP_PASSWORD=$password
                  EOF_INNER
                '';
              };

              systemd.services.lidarr-bootstrap-user = {
                description = "Bootstrap Lidarr startup user";
                wantedBy = [ "multi-user.target" ];
                wants = [ "network-online.target" "lidarr.service" "lidarr-credentials.service" ];
                after = [ "network-online.target" "lidarr.service" "lidarr-credentials.service" ];
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
                script = lidarrBootstrapUserScript;
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
                iptables -A nixos-fw -p tcp -s 192.168.68.38 --dport 8686 -j nixos-fw-accept
                iptables -A nixos-fw -p tcp -s 192.168.68.31 --dport 8686 -j nixos-fw-accept
                iptables -A nixos-fw -p tcp -s 192.168.68.41 --dport 8686 -j nixos-fw-accept
              '';
            })
        ];
    };
  };
}
