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
            services.qbittorrent.profileDir = "/appdata";
            systemd.services.qbittorrent.serviceConfig.UMask = "0002";
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
            networking.firewall.allowedTCPPorts = [ 22 6881 ];
            networking.firewall.allowedUDPPorts = [ 6881 ];
            networking.firewall.extraCommands = ''
              iptables -A nixos-fw -p tcp -s 192.168.68.38 --dport 8080 -j nixos-fw-accept
              iptables -A nixos-fw -p tcp -s 192.168.68.29 --dport 8080 -j nixos-fw-accept
              iptables -A nixos-fw -p tcp -s 192.168.68.30 --dport 8080 -j nixos-fw-accept
            '';
          })
        ];
    };
  };
}
