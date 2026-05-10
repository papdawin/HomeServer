{
  description = "Jellyseerr NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.jellyseerr = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ lib, pkgs, ... }:
            let
              jellyseerrBootstrapUsername = "papdawin";
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
            users.users.jellyseerr = {
              isSystemUser = true;
              group = "media";
              home = "/appdata/jellyseerr";
            };

            services.jellyseerr = {
              enable = true;
              port = 5055;
              configDir = "/appdata/jellyseerr";
            };

            systemd.services.jellyseerr.wants = [ "jellyseerr-migrate-appdata.service" ];
            systemd.services.jellyseerr.after = [ "jellyseerr-migrate-appdata.service" ];
            systemd.services.jellyseerr-migrate-appdata = {
              description = "Migrate legacy Jellyseerr appdata from /media/appdata to /appdata";
              before = [ "jellyseerr.service" ];
              wantedBy = [ "multi-user.target" ];
              path = with pkgs; [ coreutils findutils ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = ''
                set -eu

                legacy_dir="/media/appdata/jellyseerr"
                target_dir="/appdata/jellyseerr"

                [ -d "$legacy_dir" ] || exit 0
                [ -d "$target_dir" ] || mkdir -p "$target_dir"

                if [ -n "$(find "$target_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
                  echo "jellyseerr-migrate-appdata: target already populated, skipping migration"
                  exit 0
                fi

                cp -a "$legacy_dir/." "$target_dir/"
                chown -R jellyseerr:media "$target_dir" || true
                echo "jellyseerr-migrate-appdata: migrated data from $legacy_dir to $target_dir"
              '';
            };

            systemd.services.jellyseerr.serviceConfig = {
              DynamicUser = lib.mkForce false;
              User = "jellyseerr";
              Group = "media";
              StateDirectory = lib.mkForce "";
              # Namespace-heavy hardening can fail in unprivileged LXC (status 226/NAMESPACE).
              ProtectSystem = lib.mkForce "off";
              ProtectHome = lib.mkForce false;
              PrivateTmp = lib.mkForce false;
              PrivateDevices = lib.mkForce false;
              PrivateMounts = lib.mkForce false;
              UMask = "0002";
            };

            environment.systemPackages = with pkgs; [ curl jq ];

            systemd.services.jellyseerr-credentials = {
              description = "Prepare Jellyseerr bootstrap credentials from shared SOPS secret";
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

                jellyfin_username="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["mediaautomation"]["jellyfin"]["username"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"
                jellyfin_password="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["mediaautomation"]["jellyfin"]["password"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"
                radarr_api_key="$(read_sops_secret '["services"]["mediaautomation"]["radarr"]["apiKey"]')"
                sonarr_api_key="$(read_sops_secret '["services"]["mediaautomation"]["sonarr"]["apiKey"]')"
                jellyseerr_password="$(read_sops_secret '["services"]["jellyseerr"]["password"]')"
                [ -n "$jellyseerr_password" ] || jellyseerr_password="$(read_sops_secret '["services"]["radarr"]["password"]')"
                [ -n "$jellyseerr_password" ] || { echo "Missing services.jellyseerr.password and services.radarr.password in $sops_secret_file" >&2; exit 1; }

                cat > /run/jellyseerr-bootstrap.env <<EOF_INNER
                JELLYSEERR_JELLYFIN_HOST=jellyfin.home.arpa
                JELLYSEERR_JELLYFIN_PORT=8096
                JELLYSEERR_JELLYFIN_USERNAME=$jellyfin_username
                JELLYSEERR_JELLYFIN_PASSWORD=$jellyfin_password
                JELLYSEERR_RADARR_API_KEY=$radarr_api_key
                JELLYSEERR_SONARR_API_KEY=$sonarr_api_key
                JELLYSEERR_BOOTSTRAP_USERNAME=${jellyseerrBootstrapUsername}
                JELLYSEERR_BOOTSTRAP_PASSWORD=$jellyseerr_password
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

            networking.hosts = {
              "192.168.68.25" = [
                "jellyfin.home.arpa"
                "jellyfin"
              ];
            };

            networking.firewall.allowPing = true;
            networking.firewall.allowedTCPPorts = [ 22 5055 ];
          })
        ];
    };
  };
}
