{
  pkgs,
  inputs,
  ...
}: let
  ziti-console = inputs.openziti.packages.x86_64-linux.ziti-console;
in {
  # OpenZiti Edge Tunnel Service
  systemd.services.openziti-console = {
    wantedBy = ["multi-user.target"];

    startLimitIntervalSec = 0;
    startLimitBurst = 0;

    path = with pkgs; [nodejs];

    environment = {
      # Tmp workaround to share required creds for PoC -- use another mechanism; ex: vault
      ZAC_SERVER_CERT_CHAIN = "/var/lib/ziti-controller/pki/ziti-controller-intermediate/certs/ziti-controller-server.cert";
      ZAC_SERVER_KEY = "/var/lib/ziti-controller/pki/ziti-controller-intermediate/keys/ziti-controller-server.key";
    };

    serviceConfig = {
      Restart = "always";
      RestartSec = 5;
      StateDirectory = "ziti-console";
      WorkingDirectory = "/var/lib/ziti-console";

      ExecStartPre = let
        preScript = pkgs.writeShellApplication {
          name = "ziti-console-preScript.sh";
          text = ''
            if ! [ -f .bootstrap-pre-complete ]; then
              cp -a ${ziti-console}/* /var/lib/ziti-console

              touch .bootstrap-pre-complete
            fi

            until [ -f "$ZAC_SERVER_CERT_CHAIN" ]; do
              echo "Waiting for $ZAC_SERVER_CERT_CHAIN..."
              sleep 2
            done

            until [ -f "$ZAC_SERVER_KEY" ]; do
              echo "Waiting for $ZAC_SERVER_KEY..."
              sleep 2
            done
          '';
        };
      in "${preScript}/bin/ziti-console-preScript.sh";

      ExecStart = let
        script = pkgs.writeShellApplication {
          name = "ziti-console";
          text = ''
            node server.js
          '';
        };
      in "${script}/bin/ziti-console";
    };
  };
}
