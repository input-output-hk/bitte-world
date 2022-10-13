{
  pkgs,
  inputs,
  config,
  ...
}: let
  inherit (pkgs) lib;
  inherit (lib) mkIf mkOption;
  inherit (lib.types) bool;

  ziti-pkg = inputs.openziti.packages.x86_64-linux.ziti_latest;
  ziti-router-pkg = inputs.openziti.packages.x86_64-linux.ziti-router_latest;
  ziti-cli-functions = inputs.openziti.packages.x86_64-linux.ziti-cli-functions_latest;

  zitiController = "ziti-controller";
  zitiEdgeController = "ziti-edge-controller";
  zitiRouter = "ziti-router";
  zitiRouterHome = "/var/lib/${zitiRouter}";
  zitiNetwork = "${config.cluster.name}-zt";
  zitiEdgeRouter = "ziti-edge-router";
  zitiEdgeRouterRawName = "${zitiNetwork}-edge-router";

  routerConfigFile = builtins.toFile "${zitiEdgeRouter}.yaml" ''
    # Primary ref:     https://github.com/openziti/ziti/blob/release-next/ziti/cmd/ziti/cmd/config_templates/router.yml
    #   * The primary ref generates the quickstart router configs
    # Secondary ref:   https://github.com/openziti/ziti/blob/release-next/etc/edge.router.yml
    #   * The secondary ref contains additional config documentation notes and a few extra/different options

    v: 3

    identity:
      cert:                 "${zitiRouterHome}/pki/routers/${zitiEdgeRouter}/${zitiEdgeRouterRawName}-client.cert"
      server_cert:          "${zitiRouterHome}/pki/routers/${zitiEdgeRouter}/${zitiEdgeRouterRawName}-server.cert"
      key:                  "${zitiRouterHome}/pki/routers/${zitiEdgeRouter}/${zitiEdgeRouterRawName}-server.key"
      ca:                   "${zitiRouterHome}/pki/routers/${zitiEdgeRouter}/cas.cert"

    ctrl:
      endpoint:             tls:${zitiController}:6262

    link:
      dialers:
        - binding: transport
      listeners:
        - binding:          transport
          bind:             tls:0.0.0.0:10080
          advertise:        tls:${zitiEdgeRouter}:10080
          options:
            outQueueSize:   4

    listeners:
    # bindings of edge and tunnel requires an "edge" section below
      - binding: edge
        address: tls:0.0.0.0:3022
        options:
          advertise: ${zitiEdgeRouter}:3022
          connectTimeoutMs: 1000
          getSessionTimeout: 60s
      - binding: tunnel
        options:
          mode: host #tproxy|host


    edge:
      heartbeatIntervalSeconds: 60
      csr:
        country: US
        province: CO
        locality: Longmont
        organization: IOG
        organizationalUnit: IO
        sans:
          dns:
            - ${zitiEdgeRouter}
            - localhost
          ip:
            - "127.0.0.1"

    #transport:
    #  ws:
    #    writeTimeout: 10
    #    readTimeout: 5
    #    idleTimeout: 5
    #    pongTimeout: 60
    #    pingInterval: 54
    #    handshakeTimeout: 10
    #    readBufferSize: 4096
    #    writeBufferSize: 4096
    #    enableCompression: true
    #    server_cert: ${zitiRouterHome}/pki/routers/${zitiEdgeRouter}/server.cert
    #    key: ${zitiRouterHome}/pki/routers/${zitiEdgeRouter}/server.key

    forwarder:
      latencyProbeInterval: 10
      xgressDialQueueLength: 1000
      xgressDialWorkerCount: 128
      linkDialQueueLength: 1000
      linkDialWorkerCount: 32
  '';

  cfg = config.services.openziti-router;
in {
  options.services.openziti-router = {
    enable = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable the OpenZiti router service.
      '';
    };
    enableBashIntegration = mkOption {
      type = bool;
      # Defaults to false to avoid an auto-conflict when controller and router are on the same host
      default = false;
      description = ''
        Enable integration of OpenZiti bash completions and sourcing of the Ziti environment.

        NOTE: If multiple OpenZiti services are running on one host, the bash integration
              should be enabled for only one of the services.
      '';
    };
  };

  config = {
    # OpenZiti CLI package
    environment.systemPackages = [
      step-cli
      ziti-cli-functions
      ziti-pkg
      ziti-router-pkg
    ];

    programs.bash.interactiveShellInit = mkIf cfg.enableBashIntegration ''
      [ -f ${zitiRouterHome}/${zitiNetwork}.env ] && source ${zitiRouterHome}/${zitiNetwork}.env
    '';

    # OpenZiti DNS integration
    services.resolved.enable = true;

    # OpenZiti self hostname resolution
    networking.hosts = {
      "127.0.0.1" = [zitiEdgeRouter];
    };

    # OpenZiti Router Service
    systemd.services.openziti-router = {
      wantedBy = ["multi-user.target"];

      startLimitIntervalSec = 0;
      startLimitBurst = 0;

      environment = {
        HOME = zitiRouterHome;
        ZITI_BIN_DIR = "${zitiRouterHome}/ziti-bin";
        ZITI_CONTROLLER_INTERMEDIATE_NAME = "${zitiController}-intermediate";
        ZITI_CONTROLLER_RAWNAME = zitiController;
        ZITI_EDGE_CONTROLLER_RAWNAME = zitiEdgeController;
        ZITI_EDGE_ROUTER_HOSTNAME = zitiEdgeRouterRawName;
        ZITI_EDGE_ROUTER_PORT = "3022";
        ZITI_EDGE_ROUTER_RAWNAME = zitiEdgeRouterRawName;
        ZITI_EDGE_ROUTER_ROLES = "public";
        ZITI_HOME = zitiRouterHome;
        ZITI_NETWORK = zitiNetwork;
        ZITI_PKI_OS_SPECIFIC = "${zitiRouterHome}/pki";
      };

      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
        StateDirectory = zitiRouter;
        WorkingDirectory = zitiRouterHome;

        ExecStartPre = let
          preScript = pkgs.writeShellApplication {
            name = "${zitiRouter}-preScript.sh";
            runtimeInputs = with pkgs; [dnsutils fd ziti-pkg ziti-router-pkg];
            text = ''
              if ! [ -f .bootstrap-pre-complete ]; then
                # shellcheck disable=SC1091
                source ${ziti-cli-functions}/bin/ziti-cli-functions.sh

                mkdir -p \
                  "$ZITI_BIN_DIR" \
                  "$ZITI_PKI_OS_SPECIFIC/routers/${zitiEdgeRouter}"

                # Link the nix pkgs openziti bins to the nix store path.
                # The functions refer to these
                ln -sf ${ziti-pkg}/bin/ziti "$ZITI_BIN_DIR"/ziti
                ln -sf ${ziti-pkg}/bin/ziti-router "$ZITI_BIN_DIR"/ziti-router

                # Add this routers public IP to the PoC pki
                ZITI_EDGE_ROUTER_IP_OVERRIDE=$(dig +short myip.opendns.com @resolver1.opendns.com);
                export ZITI_EDGE_ROUTER_IP_OVERRIDE

                # Tmp workaround to share required certs for PoC -- use another mechanism; ex: vault
                while ! [ -f /var/lib/ziti-controller/pki/cas.pem ]; do
                  echo "Waiting for shared cert access..."
                  sleep 2
                done
                cp -a /var/lib/ziti-controller/pki/ziti-controller-intermediate /var/lib/ziti-router/pki/
                cp -a /var/lib/ziti-controller/pki/ziti-edge-controller-intermediate /var/lib/ziti-router/pki/
                cp -a /var/lib/ziti-controller/pki/cas.pem /var/lib/ziti-router/pki/routers/ziti-edge-router/cas.cert

                # Create PoC router pki
                createRouterPki "$ZITI_EDGE_ROUTER_RAWNAME"
                fd -t f "$ZITI_EDGE_ROUTER_RAWNAME" "pki/$ZITI_CONTROLLER_INTERMEDIATE_NAME" -x mv {} pki/routers/${zitiEdgeRouter}

                # Tmp workaround to share required certs for PoC -- use another mechanism; ex: vault
                while ! [ -f /run/keys/ziti/ziti-user ]; do
                  echo "Waiting for shared access..."
                  sleep 2
                done

                # Ensure the controller is healthy
                while [[ "$(curl -w "%{http_code}" -m 1 -s -k -o /dev/null https://${zitiEdgeController}:1280/version)" != "200" ]]; do
                  echo "waiting for https://${zitiEdgeController}:1280"
                  sleep 3
                done

                # Ensure the controller has fully bootstrapped
                sleep 10

                ziti edge login \
                  "${zitiEdgeController}:1280" \
                  -u "$(cat /run/keys/ziti/ziti-user)" \
                  -p "$(cat /run/keys/ziti/ziti-pwd)" \
                  -c /var/lib/ziti-router/pki/ziti-edge-controller-intermediate/certs/ziti-edge-controller-intermediate.cert

                FOUND=$(ziti edge list edge-routers 'name = "'"$ZITI_EDGE_ROUTER_HOSTNAME"'"' | grep -c "$ZITI_EDGE_ROUTER_HOSTNAME") || true
                if [ "$FOUND" -gt 0 ]; then
                  echo "Found existing edge-router $ZITI_EDGE_ROUTER_HOSTNAME..."
                else
                  echo "Creating edge-router $ZITI_EDGE_ROUTER_HOSTNAME identity..."
                  ziti edge create edge-router "$ZITI_EDGE_ROUTER_HOSTNAME" -o "$ZITI_HOME/$ZITI_EDGE_ROUTER_HOSTNAME.jwt" -t -a "$ZITI_EDGE_ROUTER_ROLES"
                  sleep 1
                  echo "Enrolling edge-router $ZITI_EDGE_ROUTER_HOSTNAME..."
                  ziti-router enroll ${routerConfigFile} --jwt "$ZITI_HOME/$ZITI_EDGE_ROUTER_HOSTNAME.jwt"
                  echo ""
                fi

                touch .bootstrap-pre-complete
              fi
            '';
          };
        in "${preScript}/bin/${zitiRouter}-preScript.sh";

        ExecStart = let
          script = pkgs.writeShellApplication {
            name = zitiRouter;
            text = ''
              exec ${ziti-router-pkg}/bin/ziti-router run ${routerConfigFile}
            '';
          };
        in "${script}/bin/${zitiRouter}";
      };
    };
  };
}
