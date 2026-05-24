{
  description = "Mealie NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.mealie = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ lib, pkgs, ... }: {
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
            users.users.mealie = {
              isSystemUser = true;
              group = "media";
              home = "/appdata";
              createHome = true;
            };

            services.mealie = {
              enable = true;
              listenAddress = "0.0.0.0";
              port = 9000;
              settings = {
                ALLOW_SIGNUP = "false";
                BASE_URL = "http://192.168.68.36";
                DATA_DIR = "/appdata";
                DEFAULT_GROUP = "Home";
                DEFAULT_HOUSEHOLD = "Family";
                TZ = "Europe/Budapest";
              };
            };

            services.nginx = {
              enable = true;
              recommendedProxySettings = true;
              virtualHosts."_" = {
                default = true;
                locations."/" = {
                  proxyPass = "http://127.0.0.1:9000";
                  proxyWebsockets = true;
                };
              };
            };

            systemd.services.mealie-prepare-appdata = {
              description = "Prepare Mealie appdata directory";
              before = [ "mealie.service" ];
              wantedBy = [ "multi-user.target" ];
              path = with pkgs; [ coreutils ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu
                install -d -m 0750 -o mealie -g media /appdata
              '';
            };

            systemd.services.mealie = {
              wants = [ "mealie-prepare-appdata.service" ];
              after = [ "mealie-prepare-appdata.service" ];
              serviceConfig = {
                DynamicUser = lib.mkForce false;
                User = "mealie";
                Group = "media";
                StateDirectory = lib.mkForce "";
                UMask = "0002";
              };
            };

            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = true;
                PermitRootLogin = "yes";
              };
            };

            networking.firewall.allowPing = true;
            networking.firewall.allowedTCPPorts = [ 22 80 9000 ];
          })
        ];
    };
  };
}
