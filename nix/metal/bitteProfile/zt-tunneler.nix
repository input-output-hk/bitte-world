{pkgs, ...}: let
  ziti-flake = builtins.getFlake "github:johnalotoski/openziti-bins/3019acfba44d6048238fbc40264ed3e9f88c3e50";
  ziti-edge-tunnel-pkg = ziti-flake.packages.x86_64-linux.ziti-edge-tunnel;
in {
  # OpenZiti CLI package
  environment.systemPackages = [ziti-edge-tunnel-pkg];

  # OpenZiti DNS integration
  services.resolved.enable = true;

  # OpenZiti Edge Tunnel Service
  systemd.services.ziti-edge-tunnel = {
    wantedBy = ["multi-user.target"];

    startLimitIntervalSec = 0;
    startLimitBurst = 0;

    path = with pkgs; [gnugrep gnused iproute2];

    preStart = ''
      mkdir -p /var/lib/ziti/identity
    '';

    serviceConfig = {
      Restart = "always";
      RestartSec = 5;

      ExecStart = let
        script = pkgs.writeShellApplication {
          name = "ziti-edge-tunnel";
          text = ''
            exec ${ziti-edge-tunnel-pkg}/bin/ziti-edge-tunnel run \
              --identity-dir identity \
              --verbose 3 \
              --refresh 10 \
              --dns-ip-range "100.64.0.0/10"
          '';
        };
      in "${script}/bin/ziti-edge-tunnel";

      StateDirectory = "ziti";
      WorkingDirectory = "/var/lib/ziti";
    };
  };
}
