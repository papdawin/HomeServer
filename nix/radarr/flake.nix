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
                dataDir = "/media/appdata/radarr";
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

                  qbt_username="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["mediaautomation"]["qbittorrent"]["username"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"
                  qbt_password="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["mediaautomation"]["qbittorrent"]["password"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"

                  cat > /run/radarr-bootstrap.env <<EOF_INNER
                  RADARR_QBITTORRENT_HOST=${qbittorrentHost}
                  RADARR_QBITTORRENT_PORT=${toString qbittorrentPort}
                  RADARR_QBITTORRENT_USERNAME=$qbt_username
                  RADARR_QBITTORRENT_PASSWORD=$qbt_password
                  EOF_INNER
                '';
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
