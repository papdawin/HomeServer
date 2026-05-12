{
  description = "Nextcloud NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.nextcloud = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ pkgs, ... }:
            let
              nextcloudBootstrapUsername = "papdawin";
              nextcloudBootstrapUserScript = builtins.readFile ./nextcloud-bootstrap-user.sh;
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
            users.users.nextcloud.extraGroups = [ "media" ];

            services.nextcloud = {
              enable = true;
              package = pkgs.nextcloud32;
              hostName = "192.168.68.34";
              https = false;
              home = "/appdata/nextcloud";
              config = {
                dbtype = "sqlite";
                adminuser = nextcloudBootstrapUsername;
                adminpassFile = "/run/nextcloud-admin-password";
              };
              settings = {
                trusted_domains = [
                  "192.168.68.34"
                  "nextcloud"
                ];
              };
            };

            systemd.services.nextcloud-credentials = {
              description = "Prepare Nextcloud bootstrap credentials from shared SOPS secret";
              before = [ "nextcloud-setup.service" ];
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

                password="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["nextcloud"]["password"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"
                printf '%s' "$password" >/run/nextcloud-admin-password

                cat > /run/nextcloud-bootstrap.env <<EOF_INNER
                NEXTCLOUD_BOOTSTRAP_USERNAME=${nextcloudBootstrapUsername}
                NEXTCLOUD_BOOTSTRAP_PASSWORD=$password
                EOF_INNER
              '';
            };

            systemd.services.nextcloud-setup = {
              wants = [ "nextcloud-credentials.service" ];
              after = [ "nextcloud-credentials.service" ];
            };

            systemd.services.nextcloud-bootstrap-user = {
              description = "Bootstrap Nextcloud startup user";
              wantedBy = [ "multi-user.target" ];
              wants = [ "nextcloud.service" "nextcloud-setup.service" "nextcloud-credentials.service" ];
              after = [ "nextcloud.service" "nextcloud-setup.service" "nextcloud-credentials.service" ];
              path = with pkgs; [
                bash
                coreutils
                gnugrep
                systemd
              ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = nextcloudBootstrapUserScript;
            };

            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = true;
                PermitRootLogin = "yes";
              };
            };

            networking.firewall.allowPing = true;
            networking.firewall.allowedTCPPorts = [ 22 80 ];
          })
        ];
    };
  };
}
