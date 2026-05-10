{
  description = "qBittorrent NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.qbittorrent = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ pkgs, ... }:
            let
              qbittorrentBootstrapUsername = "papdawin";
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
                "qbittorrent"
                "media"
              ];
              hashedPasswordFile = "/etc/nixos/secrets/papdawin-password-hash";
            };
            users.users.qbittorrent.extraGroups = [ "media" ];
            services.qbittorrent.enable = true;
            services.qbittorrent.profileDir = "/appdata/qbittorrent";
            systemd.services.qbittorrent.serviceConfig.UMask = "0002";
            systemd.services.qbittorrent.wants = [ "qbittorrent-migrate-appdata.service" ];
            systemd.services.qbittorrent.after = [ "qbittorrent-migrate-appdata.service" ];
            systemd.services.qbittorrent-migrate-appdata = {
              description = "Migrate legacy qBittorrent appdata from /media/appdata to /appdata";
              before = [ "qbittorrent.service" ];
              wantedBy = [ "multi-user.target" ];
              path = with pkgs; [ coreutils findutils ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu

                legacy_dir="/media/appdata/qbittorrent"
                target_dir="/appdata/qbittorrent"

                [ -d "$legacy_dir" ] || exit 0
                [ -d "$target_dir" ] || mkdir -p "$target_dir"

                if [ -n "$(find "$target_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
                  echo "qbittorrent-migrate-appdata: target already populated, skipping migration"
                  exit 0
                fi

                cp -a "$legacy_dir/." "$target_dir/"
                chown -R qbittorrent:media "$target_dir" || true
                echo "qbittorrent-migrate-appdata: migrated data from $legacy_dir to $target_dir"
              '';
            };
            environment.systemPackages = with pkgs; [ curl ];

            systemd.services.qbittorrent-credentials = {
              description = "Prepare qBittorrent bootstrap credentials from shared SOPS secret";
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

                password="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["qbittorrent"]["password"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"

                cat > /run/qbittorrent-bootstrap.env <<EOF
                QBITTORRENT_BOOTSTRAP_USERNAME=${qbittorrentBootstrapUsername}
                QBITTORRENT_BOOTSTRAP_PASSWORD=$password
                EOF
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
            networking.firewall.allowedTCPPorts = [ 22 8080 6881 ];
            networking.firewall.allowedUDPPorts = [ 6881 ];
          })
        ];
    };
  };
}
