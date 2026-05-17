{
  description = "OpenClaw NixOS container for Proxmox LXC";
  nixConfig = {
    extra-substituters = [ "https://cache.garnix.io" ];
    extra-trusted-public-keys = [
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nix-openclaw = {
      # Pin nix-openclaw to a known commit so rebuilds stay stable and cacheable.
      url = "github:openclaw/nix-openclaw/64d410666821866c565e048a4d07d6cf5d8e494e";
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
          ({ lib, pkgs, ... }: {
            system.stateVersion = "25.11";
            boot.isContainer = true;
            boot.tmp.useTmpfs = false;

            nix.settings = {
              build-dir = "/var/lib/nix-build";
              extra-substituters = [ "https://cache.garnix.io" ];
              extra-trusted-public-keys = [
                "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
              ];
              auto-optimise-store = true;
            };
            nix.gc = {
              automatic = true;
              dates = "daily";
              options = "--delete-older-than 3d";
            };

            systemd.mounts = [
              {
                enable = false;
                where = "/sys/kernel/debug";
              }
            ];

            systemd.services.openclaw-prepare-appdata = {
              description = "Prepare OpenClaw appdata directory";
              before = [ "openclaw-gateway.service" ];
              wantedBy = [ "multi-user.target" ];
              path = with pkgs; [ coreutils ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu
                install -d -m 0750 /appdata
                chown -R openclaw:openclaw /appdata || true
                chmod -R u+rwX /appdata || true
              '';
            };

            systemd.services.openclaw-gateway.wants = [ "openclaw-prepare-appdata.service" ];
            systemd.services.openclaw-gateway.after = [ "openclaw-prepare-appdata.service" ];

            services.openclaw-gateway = {
              enable = true;
              package = nix-openclaw.packages.${pkgs.system}.openclaw-gateway;
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
                OPENCLAW_STATE_DIR = lib.mkForce "/appdata";
                XDG_CONFIG_HOME = "/appdata";
                HOME = "/appdata";
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
