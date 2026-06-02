{
  description = "AdGuard Home NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.adguardhome = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ pkgs, ... }: {
            system.stateVersion = "25.11";
            boot.isContainer = true;

            systemd.mounts = [
              {
                enable = false;
                where = "/sys/kernel/debug";
              }
            ];

            users.mutableUsers = false;
            users.users.papdawin = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              hashedPasswordFile = "/etc/nixos/secrets/papdawin-password-hash";
            };

            services.adguardhome = {
              enable = true;
              mutableSettings = true;
              host = "0.0.0.0";
              port = 3000;
              settings = {
                dns = {
                  bind_hosts = [ "0.0.0.0" ];
                  port = 53;
                  upstream_dns = [
                    "192.168.68.1"
                    "1.1.1.1"
                    "9.9.9.9"
                  ];
                  bootstrap_dns = [
                    "192.168.68.1"
                    "1.1.1.1"
                    "9.9.9.9"
                  ];
                };
                filtering = {
                  protection_enabled = true;
                  rewrites_enabled = true;
                  rewrites = [
                    {
                      domain = "*.home.papdavid.eu";
                      answer = "192.168.68.38";
                      enabled = true;
                    }
                  ];
                };
              };
            };

            environment.systemPackages = with pkgs; [
              bind.dnsutils
              curl
            ];

            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = true;
                PermitRootLogin = "yes";
              };
            };

            networking.firewall.allowPing = true;
            networking.firewall.allowedTCPPorts = [ 22 53 ];
            networking.firewall.allowedUDPPorts = [ 53 ];
            networking.firewall.extraCommands = ''
              iptables -A nixos-fw -p tcp -s 192.168.68.38 --dport 3000 -j nixos-fw-accept
            '';
          })
        ];
    };
  };
}
