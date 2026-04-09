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
