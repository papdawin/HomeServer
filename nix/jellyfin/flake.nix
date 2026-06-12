{
  description = "Jellyfin NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.jellyfin = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ pkgs, ... }:
            let
              jellyfinBootstrapUsername = "papdawin";
              jellyfinBootstrapScript = builtins.readFile ./jellyfin-bootstrap-user.sh;
              jellyfinBootstrapLibrariesScript = builtins.readFile ./jellyfin-bootstrap-libraries.sh;
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
                "jellyfin"
                "media"
              ];
              hashedPasswordFile = "/etc/nixos/secrets/papdawin-password-hash";
            };
            users.users.jellyfin.extraGroups = [ "media" ];

            services.jellyfin = {
              enable = true;
              dataDir = "/appdata";
              configDir = "/appdata/config";
              logDir = "/appdata/log";
              cacheDir = "/appdata/cache";
            };
            environment.systemPackages = with pkgs; [ curl ];

            systemd.services.jellyfin-credentials = {
              description = "Prepare Jellyfin bootstrap credentials from shared SOPS secret";
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

                password="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["jellyfin"]["password"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"

                cat > /run/jellyfin-bootstrap.env <<EOF
                JELLYFIN_BOOTSTRAP_USERNAME=${jellyfinBootstrapUsername}
                JELLYFIN_BOOTSTRAP_PASSWORD=$password
                EOF
              '';
            };

            systemd.services.jellyfin-bootstrap = {
              description = "Bootstrap Jellyfin startup user";
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" "jellyfin.service" "jellyfin-credentials.service" ];
              after = [ "network-online.target" "jellyfin.service" "jellyfin-credentials.service" ];
              path = with pkgs; [
                bash
                coreutils
                curl
                gawk
                gnugrep
                gnused
                systemd
              ];
              serviceConfig = {
                Type = "oneshot";
                Restart = "on-failure";
                RestartSec = "15s";
              };
              script = jellyfinBootstrapScript;
            };

            systemd.services.jellyfin-bootstrap-libraries = {
              description = "Bootstrap Jellyfin media libraries";
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" "jellyfin.service" "jellyfin-credentials.service" "jellyfin-bootstrap.service" ];
              after = [ "network-online.target" "jellyfin.service" "jellyfin-credentials.service" "jellyfin-bootstrap.service" ];
              path = with pkgs; [
                bash
                coreutils
                curl
                jq
                gnugrep
                gnused
                systemd
              ];
              serviceConfig = {
                Type = "oneshot";
                Restart = "on-failure";
                RestartSec = "15s";
              };
              script = jellyfinBootstrapLibrariesScript;
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
              iptables -A nixos-fw -p tcp -s 192.168.68.38 --dport 8096 -j nixos-fw-accept
              iptables -A nixos-fw -p tcp -s 192.168.68.32 --dport 8096 -j nixos-fw-accept
            '';
          })
        ];
    };
  };
}
