{
  pkgs,
  inputs,
  ...
}: let
  ziti-console = inputs.openziti.packages.x86_64-linux.ziti-console;
in {
  # OpenZiti Edge Tunnel Service
  systemd.services.ziti-console = {
    wantedBy = ["multi-user.target"];

    startLimitIntervalSec = 0;
    startLimitBurst = 0;

    path = with pkgs; [nodejs];

    # preStart = ''
    #   mkdir -p /var/lib/ziti/identity
    # '';

    serviceConfig = {
      Restart = "always";
      RestartSec = 5;

      ExecStart = let
        script = pkgs.writeShellApplication {
          name = "ziti-console";
          text = ''
            cp -a ${ziti-console}/_napalm-install/* /var/lib/ziti-console
            node server.js
          '';
        };
      in "${script}/bin/ziti-console";

      StateDirectory = "ziti-console";
      WorkingDirectory = "/var/lib/ziti-console";
    };
  };
}
