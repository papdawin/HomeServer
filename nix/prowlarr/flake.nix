{
  description = "Prowlarr NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.prowlarr = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ lib, pkgs, ... }:
            let
              prowlarrBootstrapUsername = "papdawin";
              prowlarrBootstrapUserScript = builtins.readFile ./prowlarr-bootstrap-user.sh;
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
            users.users.prowlarr = {
              isSystemUser = true;
              group = "media";
              home = "/media/appdata/prowlarr";
            };

            services.prowlarr = {
              enable = true;
              settings.server = {
                bindaddress = "*";
                port = 9696;
              };
            };

            systemd.services.prowlarr.serviceConfig = {
              DynamicUser = lib.mkForce false;
              User = "prowlarr";
              Group = "media";
              StateDirectory = lib.mkForce "";
              ExecStart = lib.mkForce "${lib.getExe pkgs.prowlarr} -nobrowser -data=/media/appdata/prowlarr";
              UMask = "0002";
            };
            systemd.services.prowlarr.environment.HOME = lib.mkForce "/media/appdata/prowlarr";

            environment.systemPackages = with pkgs; [ curl jq ];

            systemd.services.prowlarr-credentials = {
              description = "Prepare Prowlarr bootstrap credentials from shared SOPS secret";
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

                password="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["prowlarr"]["password"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"

                cat > /run/prowlarr-bootstrap.env <<EOF
                PROWLARR_BOOTSTRAP_USERNAME=${prowlarrBootstrapUsername}
                PROWLARR_BOOTSTRAP_PASSWORD=$password
                EOF
              '';
            };

            systemd.services.prowlarr-bootstrap-user = {
              description = "Bootstrap Prowlarr startup user";
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" "prowlarr.service" "prowlarr-credentials.service" ];
              after = [ "network-online.target" "prowlarr.service" "prowlarr-credentials.service" ];
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
              script = prowlarrBootstrapUserScript;
            };

            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = true;
                PermitRootLogin = "yes";
              };
            };

            networking.firewall.allowPing = true;
            networking.firewall.allowedTCPPorts = [ 22 9696 ];
          })
        ];
    };
  };
}
