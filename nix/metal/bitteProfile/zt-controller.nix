{
  pkgs,
  inputs,
  config,
  ...
}: let
  ziti-flake = builtins.getFlake "github:johnalotoski/openziti-bins/3019acfba44d6048238fbc40264ed3e9f88c3e50";
  ziti-pkg = ziti-flake.packages.x86_64-linux.ziti;
  ziti-cli-functions = inputs.self.x86_64-linux.openziti.packages.ziti-cli-functions;

  zitiHome = "/var/lib/ziti-controller";
  zitiNetwork = "${config.cluster.name}-zt";
  controllerConfigFile = builtins.toFile "ziti-edge-controller.yaml" ''
    # Primary ref:     https://github.com/openziti/ziti/blob/release-next/ziti/cmd/ziti/cmd/config_templates/controller.yml
    #   * The primary ref generates the quickstart controller configs
    # Secondary ref:   https://github.com/openziti/ziti/blob/release-next/etc/ctrl.with.edge.yml
    #   * The secondary ref contains additional config documentation notes and a few extra/different options

    v: 3

    #trace:
    #  path: "controller.trace"

    #profile:
    #  memory:
    #    path: ctrl.memprof

    db:                     "/var/lib/ziti-controller/db/ctrl.db"

    identity:
      cert:                 "/var/lib/ziti-controller/pki/ziti-controller-intermediate/certs/ziti-controller-client.cert"
      server_cert:          "/var/lib/ziti-controller/pki/ziti-controller-intermediate/certs/ziti-controller-server.chain.pem"
      key:                  "/var/lib/ziti-controller/pki/ziti-controller-intermediate/keys/ziti-controller-server.key"
      ca:                   "/var/lib/ziti-controller/pki/cas.pem"

    # Network Configuration
    #
    # Configure how the controller will establish and manage the overlay network, and routing operations on top of
    # the network.
    #
    #network:

      # routeTimeoutSeconds controls the number of seconds the controller will wait for a route attempt to succeed.
      #routeTimeoutSeconds:  10

      # createCircuitRetries controls the number of retries that will be attempted to create a path (and terminate it)
      # for new circuits.
      #createCircuitRetries: 2

      # pendingLinkTimeoutSeconds controls how long we'll wait before creating a new link between routers where
      # there isn't an established link, but a link request has been sent
      #pendingLinkTimeoutSeconds: 10

      # Defines the period that the controller re-evaluates the performance of all of the circuits
      # running on the network.
      #
      #cycleSeconds:         15

      # Sets router minimum cost. Defaults to 10
      #minRouterCost: 10

      # Sets how often a new control channel connection can take over for a router with an existing control channel connection
      # Defaults to 1 minute
      #routerConnectChurnLimit: 1m

      # Sets the latency of link when it's first created. Will be overwritten as soon as latency from the link is actually
      # reported from the routers. Defaults to 65 seconds.
      #initialLinkLatency: 65s

      #smart:
        #
        # Defines the fractional upper limit of underperforming circuits that are candidates to be re-routed. If
        # smart routing detects 100 circuits that are underperforming, and `smart.rerouteFraction` is set to `0.02`,
        # then the upper limit of circuits that will be re-routed in this `cycleSeconds` period will be limited to
        # 2 (2% of 100).
        #
        #rerouteFraction:    0.02
        #
        # Defines the hard upper limit of underperforming circuits that are candidates to be re-routed. If smart
        # routing detects 100 circuits that are underperforming, and `smart.rerouteCap` is set to `1`, and
        # `smart.rerouteFraction` is set to `0.02`, then the upper limit of circuits that will be re-routed in this
        # `cycleSeconds` period will be limited to 1.
        #
        #rerouteCap:         4

    # the endpoint that routers will connect to the controller over.
    ctrl:
      #options:
      # (optional) settings
      # set the maximum number of connect requests that are buffered and waiting to be acknowledged (1 to 5000, default 1)
      #maxQueuedConnects:      1
      # the maximum number of connects that have  begun hello synchronization (1 to 1000, default 16)
      #maxOutstandingConnects: 16
      # the number of milliseconds to wait before a hello synchronization fails and closes the connection (30ms to 60000ms, default: 1000ms)
      #connectTimeoutMs:       1000
      listener:             tls:0.0.0.0:6262

    # the endpoint that management tools connect to the controller over.
    mgmt:
      #options:
      # (optional) settings
      # set the maximum number of connect requests that are buffered and waiting to be acknowledged (1 to 5000, default 1)
      #maxQueuedConnects:      1
      # the maximum number of connects that have  begun hello synchronization (1 to 1000, default 16)
      #maxOutstandingConnects: 16
      # the number of milliseconds to wait before a hello synchronization fails and closes the connection (30ms to 60000ms, default: 1000ms)
      #connectTimeoutMs:       1000
      listener:             tls:0.0.0.0:10000

    #metrics:
    #  influxdb:
    #    url:                http://localhost:8086
    #    database:           ziti

    # xctrl_example
    #
    #example:
    #  enabled:              false
    #  delay:                5s

    healthChecks:
      boltCheck:
        # How often to try entering a bolt read tx. Defaults to 30 seconds
        interval: 30s
        # When to time out the check. Defaults to 20 seconds
        timeout: 20s
        # How long to wait before starting the check. Defaults to 30 seconds
        initialDelay: 30s

    # By having an 'edge' section defined, the ziti-controller will attempt to parse the edge configuration. Removing this
    # section, commenting out, or altering the name of the section will cause the edge to not run.
    edge:
      # This section represents the configuration of the Edge API that is served over HTTPS
      api:
        #(optional, default 90s) Alters how frequently heartbeat and last activity values are persisted
        # activityUpdateInterval: 90s
        #(optional, default 250) The number of API Sessions updated for last activity per transaction
        # activityUpdateBatchSize: 250
        # sessionTimeout - optional, default 30m
        # The number of minutes before an Edge API session will time out. Timeouts are reset by
        # API requests and connections that are maintained to Edge Routers
        sessionTimeout: 30m
        # address - required
        # The default address (host:port) to use for enrollment for the Client API. This value must match one of the addresses
        # defined in this Controller.WebListener.'s bindPoints.
        address: ziti-edge-controller:1280
      # This section is used to define option that are used during enrollment of Edge Routers, Ziti Edge Identities.
      enrollment:
        # signingCert - required
        # A Ziti Identity configuration section that specifically makes use of the cert and key fields to define
        # a signing certificate from the PKI that the Ziti environment is using to sign certificates. The signingCert.cert
        # will be added to the /.well-known CA store that is used to bootstrap trust with the Ziti Controller.
        signingCert:
          cert: /var/lib/ziti-controller/pki/${zitiNetwork}-signing-intermediate/certs/${zitiNetwork}-signing-intermediate.cert
          key:  /var/lib/ziti-controller/pki/${zitiNetwork}-signing-intermediate/keys/${zitiNetwork}-signing-intermediate.key
        # edgeIdentity - optional
        # A section for identity enrollment specific settings
        edgeIdentity:
          # duration - optional, default 180m
          # The length of time that a Ziti Edge Identity enrollment should remain valid. After
          # this duration, the enrollment will expire and no longer be usable.
          duration: 180m
        # edgeRouter - Optional
        # A section for edge router enrollment specific settings.
        edgeRouter:
          # duration - optional, default 180m
          # The length of time that a Ziti Edge Router enrollment should remain valid. After
          # this duration, the enrollment will expire and no longer be usable.
          duration: 180m

    # web
    # Defines webListeners that will be hosted by the controller. Each webListener can host many APIs and be bound to many
    # bind points.
    web:
      # name - required
      # Provides a name for this listener, used for logging output. Not required to be unique, but is highly suggested.
      - name: client-management
        # bindPoints - required
        # One or more bind points are required. A bind point specifies an interface (interface:port string) that defines
        # where on the host machine the webListener will listen and the address (host:port) that should be used to
        # publicly address the webListener(i.e. mydomain.com, localhost, 127.0.0.1). This public address may be used for
        # incoming address resolution as well as used in responses in the API.
        bindPoints:
          #interface - required
          # A host:port string on which network interface to listen on. 0.0.0.0 will listen on all interfaces
          - interface: 0.0.0.0:1280
            # address - required
            # The public address that external incoming requests will be able to resolve. Used in request processing and
            # response content that requires full host:port/path addresses.
            address: ziti-edge-controller:1280
        # identity - optional
        # Allows the webListener to have a specific identity instead of defaulting to the root 'identity' section.
        identity:
          ca:          "/var/lib/ziti-controller/pki/ziti-edge-controller-intermediate/certs/ziti-edge-controller-intermediate.cert"
          key:         "/var/lib/ziti-controller/pki/ziti-edge-controller-intermediate/keys/ziti-edge-controller-server.key"
          server_cert: "/var/lib/ziti-controller/pki/ziti-edge-controller-intermediate/certs/ziti-edge-controller-server.chain.pem"
          cert:        "/var/lib/ziti-controller/pki/ziti-edge-controller-intermediate/certs/ziti-edge-controller-client.cert"
        # options - optional
        # Allows the specification of webListener level options - mainly dealing with HTTP/TLS settings. These options are
        # used for all http servers started by the current webListener.
        options:
          # idleTimeoutMs - optional, default 5000ms
          # The maximum amount of idle time in milliseconds allowed for pipelined HTTP requests. Setting this too high
          # can cause resources on the host to be consumed as clients remain connected and idle. Lowering this value
          # will cause clients to reconnect on subsequent HTTPs requests.
          idleTimeout: 5000ms  #http timeouts, new
          # readTimeoutMs - optional, default 5000ms
          # The maximum amount of time in milliseconds http servers will wait to read the first incoming requests. A higher
          # value risks consuming resources on the host with clients that are acting bad faith or suffering from high latency
          # or packet loss. A lower value can risk losing connections to high latency/packet loss clients.
          readTimeout: 5000ms
          # writeTimeoutMs - optional, default 100000ms
          # The total maximum time in milliseconds that the http server will wait for a single requests to be received and
          # responded too. A higher value can allow long-running requests to consume resources on the host. A lower value
          # can risk ending requests before the server has a chance to respond.
          writeTimeout: 100000ms
          # minTLSVersion - optional, default TLS1.2
          # The minimum version of TSL to support
          minTLSVersion: TLS1.2
          # maxTLSVersion - optional, default TLS1.3
          # The maximum version of TSL to support
          maxTLSVersion: TLS1.3
        # apis - required
        # Allows one or more APIs to be bound to this webListener
        apis:
          # binding - required
          # Specifies an API to bind to this webListener. Built-in APIs are
          #   - edge-management
          #   - edge-client
          #   - fabric-management
          - binding: edge-management
            # options - arg optional/required
            # This section is used to define values that are specified by the API they are associated with.
            # These settings are per API. The example below is for the 'edge-api' and contains both optional values and
            # required values.
            options: { }
          - binding: edge-client
            options: { }
  '';
in {
  # OpenZiti CLI package
  environment.systemPackages = [ziti-cli-functions ziti-pkg];

  programs.bash.interactiveShellInit = ''
    if command -v ziti >/dev/null; then
      source <(${ziti-pkg}/bin/ziti completion bash)
    fi

    [ -f ${zitiHome}/${zitiNetwork}.env ] && source ${zitiHome}/${zitiNetwork}.env
  '';

  # OpenZiti DNS integration
  services.resolved.enable = true;

  # OpenZiti self hostname resolution
  networking.hosts = {
    "127.0.0.1" = ["ziti-edge-controller"];
  };

  # OpenZiti Edge Tunnel Service
  systemd.services.ziti-controller = {
    wantedBy = ["multi-user.target"];

    startLimitIntervalSec = 0;
    startLimitBurst = 0;

    # path = with pkgs; [gnugrep gnused iproute2];

    environment = let
      zitiEdgeRouterRawName = "${zitiNetwork}-edge-router";
    in {
      HOME = "/var/lib/ziti-controller";
      ZITI_BIN_DIR = "/var/lib/ziti-controller/ziti-bin";
      ZITI_CONTROLLER_RAWNAME = "ziti-controller";
      ZITI_EDGE_CONTROLLER_RAWNAME = "ziti-edge-controller";
      ZITI_EDGE_ROUTER_HOSTNAME = zitiEdgeRouterRawName;
      ZITI_EDGE_ROUTER_PORT = "3022";
      ZITI_EDGE_ROUTER_RAWNAME = zitiEdgeRouterRawName;
      ZITI_EDGE_ROUTER_ROLES = zitiEdgeRouterRawName;
      ZITI_HOME = "/var/lib/ziti-controller";
      ZITI_NETWORK = zitiNetwork;
    };

    serviceConfig = {
      Restart = "always";
      RestartSec = 5;
      StateDirectory = "ziti-controller";
      WorkingDirectory = "/var/lib/ziti-controller";

      ExecStartPre = let
        preScript = pkgs.writeShellApplication {
          name = "ziti-controller-preScript.sh";
          runtimeInputs = with pkgs; [ziti-pkg];
          text = ''
            if ! [ -f .bootstrap-pre-complete ]; then
              # shellcheck disable=SC1091
              source ${ziti-cli-functions}/bin/ziti-cli-functions.sh

              # Generate the initial ziti controller environment vars
              generateEnvFile

              # Link the nix pkgs openziti bins to the nix store path.
              # The functions refer to these
              ln -sf ${ziti-pkg}/bin/ziti "$ZITI_BIN_ROOT"/ziti
              ln -sf ${ziti-pkg}/bin/ziti-controller "$ZITI_BIN_ROOT"/ziti-controller
              ln -sf ${ziti-pkg}/bin/ziti-router "$ZITI_BIN_ROOT"/ziti-router
              ln -sf ${ziti-pkg}/bin/ziti-tunnel "$ZITI_BIN_ROOT"/ziti-tunnel

              # Create PoC pki
              createPki

              # Finish the cert setup (taken from createControllerConfig fn)
              cat "$ZITI_CTRL_IDENTITY_SERVER_CERT" > "$ZITI_CTRL_IDENTITY_CA"
              cat "$ZITI_SIGNING_CERT" >> "$ZITI_CTRL_IDENTITY_CA"
              echo -e "wrote CA file to: $ZITI_CTRL_IDENTITY_CA"

              # Initialize the database with the admin user:
              "$ZITI_BIN_DIR/ziti-controller" edge init ${controllerConfigFile} -u "$ZITI_USER" -p "$ZITI_PWD"

              touch .bootstrap-pre-complete
            fi
          '';
        };
      in "${preScript}/bin/ziti-controller-preScript.sh";

      ExecStart = let
        script = pkgs.writeShellApplication {
          name = "ziti-controller";
          text = ''
            exec ${ziti-pkg}/bin/ziti-controller run ${controllerConfigFile}
          '';
        };
      in "${script}/bin/ziti-controller";

      ExecStartPost = let
        postScript = pkgs.writeShellApplication {
          name = "ziti-controller-postScript.sh";
          runtimeInputs = with pkgs; [curl ziti-pkg];
          text = ''
            if ! [ -f .bootstrap-post-complete ]; then
              # shellcheck disable=SC1091
              source ${ziti-cli-functions}/bin/ziti-cli-functions.sh

              # shellcheck disable=SC1090
              source "$ZITI_HOME/$ZITI_NETWORK.env"

              while true; do
                echo "waiting for https://$ZITI_EDGE_CTRL_ADVERTISED_HOST_PORT"
                sleep 2
                curl -s -o /dev/null --fail -k "https://$ZITI_EDGE_CTRL_ADVERTISED_HOST_PORT" && break
              done

              zitiLogin &> /dev/null
              ziti edge create edge-router-policy all-endpoints-public-routers --edge-router-roles "#public" --identity-roles "#all"
              ziti edge create service-edge-router-policy all-routers-all-services --edge-router-roles "#all" --service-roles "#all"

              touch .bootstrap-post-complete
            fi
          '';
        };
      in "${postScript}/bin/ziti-controller-postScript.sh";
    };
  };
}
