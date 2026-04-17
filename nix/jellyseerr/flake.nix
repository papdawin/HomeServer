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
              home = "/media/appdata/jellyseerr";
            };

            systemd.tmpfiles.rules = [
              "z /media/appdata 2775 root media -"
              "d /media/appdata/jellyseerr 2775 jellyseerr media -"
              "d /media/appdata/jellyseerr/logs 2775 jellyseerr media -"
            ];

            services.jellyseerr = {
              enable = true;
              port = 5055;
              configDir = "/media/appdata/jellyseerr";
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
                jellyseerr_password="$(read_sops_secret '["services"]["jellyseerr"]["password"]')"
                [ -n "$jellyseerr_password" ] || jellyseerr_password="$(read_sops_secret '["services"]["radarr"]["password"]')"
                [ -n "$jellyseerr_password" ] || { echo "Missing services.jellyseerr.password and services.radarr.password in $sops_secret_file" >&2; exit 1; }

                cat > /run/jellyseerr-bootstrap.env <<EOF_INNER
                JELLYSEERR_JELLYFIN_HOST=jellyfin.home.arpa
                JELLYSEERR_JELLYFIN_PORT=8096
                JELLYSEERR_JELLYFIN_USERNAME=$jellyfin_username
                JELLYSEERR_JELLYFIN_PASSWORD=$jellyfin_password
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
