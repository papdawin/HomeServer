{
  description = "OpenClaw NixOS container for Proxmox LXC";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nix-openclaw, ... }: {
    nixosConfigurations.openclaw = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          nix-openclaw.nixosModules.openclaw-gateway
          ({ ... }: {
            system.stateVersion = "25.11";
            boot.isContainer = true;

            systemd.mounts = [
              {
                enable = false;
                where = "/sys/kernel/debug";
              }
            ];

            nixpkgs.overlays = [ nix-openclaw.overlays.default ];

            services.openclaw-gateway = {
              enable = true;
              config = {
                gateway = {
                  mode = "local";
                  bind = "lan";
                  auth = {
                    mode = "token";
                    token = "change-me-openclaw-gateway-token";
                  };
                  controlUi = {
                    # Required for non-loopback browser clients.
                    allowedOrigins = [
                      "http://192.168.68.27:18789"
                      "http://192.168.68.120:18789"
                      "http://openclaw:18789"
                      "http://localhost:18789"
                      "http://127.0.0.1:18789"
                    ];

                    # Break-glass for LAN HTTP access from other devices.
                    # Prefer HTTPS/Tailscale and disable this afterwards.
                    dangerouslyDisableDeviceAuth = true;
                  };
                };
              };
              environment = {
                OPENCLAW_NIX_MODE = "1";
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
            networking.firewall.allowedTCPPorts = [ 22 18789 ];
          })
        ];
    };
  };
}
