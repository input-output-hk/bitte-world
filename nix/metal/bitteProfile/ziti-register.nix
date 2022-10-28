{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkIf;
in {
  systemd.services.ziti-controller-rest-service =
    mkIf config.services.ziti-controller.enable
    (pkgs.consulRegister {
      pkiFiles.caCertFile = "/etc/ssl/certs/ca.pem";
      systemdServiceParent = "ziti-controller";
      service = {
        name = "ziti-controller-rest";
        port = config.services.ziti-controller.portRestApi;
        tags = [
          "ziti"
          "ziti-controller-rest"
          "ingress"
          "traefik.enable=true"
          "traefik.tcp.routers.ziti-controller-rest.service.ziti-controller-rest-service"
          "traefik.tcp.routers.ziti-controller-rest.entrypoints=ziti-controller-rest"
          "traefik.tcp.routers.ziti-controller-rest.rule=HostSNI(`*`)"
          "traefik.tcp.routers.ziti-controller-rest.tls=false"
        ];

        checks = {
          ziti-controller-rest-tcp = {
            interval = "60s";
            timeout = "5s";
            tcp = "127.0.0.1:${toString config.services.ziti-controller.portRestApi}";
          };
        };
      };
    })
    .systemdService;

  systemd.services.ziti-controller-mgmt-service =
    mkIf config.services.ziti-controller.enable
    (pkgs.consulRegister {
      pkiFiles.caCertFile = "/etc/ssl/certs/ca.pem";
      systemdServiceParent = "ziti-controller";
      service = {
        name = "ziti-controller-mgmt";
        port = config.services.ziti-controller.portManagementApi;
        tags = [
          "ziti"
          "ziti-controller-mgmt"
          "ingress"
          "traefik.enable=true"
          "traefik.tcp.routers.ziti-controller-mgmt.service.ziti-controller-mgmt-service"
          "traefik.tcp.routers.ziti-controller-mgmt.entrypoints=ziti-controller-mgmt"
          "traefik.tcp.routers.ziti-controller-mgmt.rule=HostSNI(`*`)"
          "traefik.tcp.routers.ziti-controller-mgmt.tls=false"
        ];

        checks = {
          ziti-controller-mgmt-tcp = {
            interval = "60s";
            timeout = "5s";
            tcp = "127.0.0.1:${toString config.services.ziti-controller.portManagementApi}";
          };
        };
      };
    })
    .systemdService;

  systemd.services.ziti-router-edge-service =
    mkIf config.services.ziti-router.enable
    (pkgs.consulRegister {
      pkiFiles.caCertFile = "/etc/ssl/certs/ca.pem";
      systemdServiceParent = "ziti-router";
      service = {
        name = "ziti-router-edge";
        port = config.services.ziti-router.portEdgeConnection;
        tags = [
          "ziti"
          "ziti-router-edge"
          "ingress"
          "traefik.enable=true"
          "traefik.tcp.routers.ziti-router-edge.service.ziti-router-edge-service"
          "traefik.tcp.routers.ziti-router-edge.entrypoints=ziti-router-edge"
          "traefik.tcp.routers.ziti-router-edge.rule=HostSNI(`*`)"
          "traefik.tcp.routers.ziti-router-edge.tls=false"
        ];

        checks = {
          ziti-router-edge-tcp = {
            interval = "60s";
            timeout = "5s";
            tcp = "127.0.0.1:${toString config.services.ziti-router.portEdgeConnection}";
          };
        };
      };
    })
    .systemdService;

  systemd.services.ziti-router-fabric-service =
    mkIf config.services.ziti-router.enable
    (pkgs.consulRegister {
      pkiFiles.caCertFile = "/etc/ssl/certs/ca.pem";
      systemdServiceParent = "ziti-router";
      service = {
        name = "ziti-router-fabric";
        port = config.services.ziti-router.portEdgeConnection;
        tags = [
          "ziti"
          "ziti-router-fabric"
          "ingress"
          "traefik.enable=true"
          "traefik.tcp.routers.ziti-router-fabric.service.ziti-router-fabric-service"
          "traefik.tcp.routers.ziti-router-fabric.entrypoints=ziti-router-fabric"
          "traefik.tcp.routers.ziti-router-fabric.rule=HostSNI(`*`)"
          "traefik.tcp.routers.ziti-router-fabric.tls=false"
        ];

        checks = {
          ziti-router-fabric-tcp = {
            interval = "60s";
            timeout = "5s";
            tcp = "127.0.0.1:${toString config.services.ziti-router.portFabricLinks}";
          };
        };
      };
    })
    .systemdService;

  systemd.services.ziti-console-service =
    mkIf config.services.ziti-console.enable
    (pkgs.consulRegister {
      pkiFiles.caCertFile = "/etc/ssl/certs/ca.pem";
      service = {
        name = "ziti-console";
        port = config.services.ziti-console.portHttp;
        tags = [
          "ziti"
          "ziti-console"
          "ingress"
          "traefik.enable=true"
          "traefik.http.routers.ziti-console.rule=Host(`zt.${config.cluster.domain}`)"
          "traefik.http.routers.ziti-console.entrypoints=https"
          "traefik.http.routers.ziti-console.middlewares=oauth-auth-redirect@file"
          "traefik.http.routers.ziti-console.tls=true"
          "traefik.http.routers.ziti-console.tls.certresolver=acme"
        ];

        checks = {
          ziti-console-http = {
            interval = "60s";
            timeout = "5s";
            http = "http://127.0.0.1:${toString config.services.ziti-console.portHttp}/login";
          };
        };
      };
    })
    .systemdService;
}
