{
  inputs,
  cell,
}: let
  inherit (inputs) nixpkgs openziti;
  inherit (inputs.bitte-cells) patroni tempo;
in {
  default = {
    self,
    lib,
    pkgs,
    config,
    terralib,
    bittelib,
    ...
  }: let
    inherit (self.inputs) bitte;
    inherit (config) cluster;
    securityGroupRules = bittelib.securityGroupRules config;
  in {
    secrets.encryptedRoot = ./encrypted;
    # age.encryptedRoot = ./encrypted-prem;

    cluster = {
      s3CachePubKey = lib.fileContents ./encrypted/nix-public-key-file;
      flakePath = "${inputs.self}";
      vbkBackend = "local";
      builder = "monitoring";
      transitGateway = {
        enable = true;
        transitRoutes = [
          {
            gatewayCoreNodeName = "zt";
            cidrRange = "10.10.0.0/24";
          }
          {
            # Matches the equinix assigned project private IP block
            gatewayCoreNodeName = "zt";
            cidrRange = "10.12.100.0/25";
          }
        ];
      };

      autoscalingGroups = let
        defaultModules = [
          bitte.profiles.client
          bitte.profiles.nomad-follower
          "${self.inputs.nixpkgs}/nixos/modules/profiles/headless.nix"
          ({lib, ...}: {
            services.glusterfs.enable = lib.mkForce false;

            profiles.auxiliaries.builder.remoteBuilder.buildMachine.supportedFeatures = ["big-parallel"];
            virtualisation.containers.ociSeccompBpfHook.enable = true;

            systemd.services.nomad.serviceConfig = {
              JobTimeoutSec = "600s";
              JobRunningTimeoutSec = "600s";
            };
          })
        ];

        mkAsgs = region: desiredCapacity: instanceType: volumeSize: node_class: asgSuffix: opts: extraConfig:
          {
            inherit region desiredCapacity instanceType volumeSize node_class asgSuffix;
            modules =
              defaultModules
              ++ lib.optional (opts ? withPatroni && opts.withPatroni == true) (patroni.nixosProfiles.client node_class);
          }
          // extraConfig;
        # -------------------------
        # For each list item below which represents an auto-scaler machine(s),
        # an autoscaling group name will be created in the form of:
        #
        #   client-$REGION-$INSTANCE_TYPE
        #
        # This works for most cases, but if there is a use case where
        # machines of the same instance type and region need to be
        # separated into different auto-scaling groups, this can be done by
        # setting a string attribute of `asgSuffix` in the list items needed.
        #
        # If used, asgSuffix must be a string matching a regex of: ^[A-Za-z0-9]$
        # Otherwise, nix will throw an error.
        #
        # Autoscaling groups which utilize an asgSuffix will be named in the form:
        #
        #   client-$REGION-$INSTANCE_TYPE-$ASG_SUFFIX
      in
        lib.listToAttrs (lib.forEach [
            (mkAsgs "eu-central-1" 3 "t3a.medium" 100 "patroni" "patroni" {withPatroni = true;} {})
            (mkAsgs "eu-central-1" 1 "t3a.medium" 100 "tempo" "tempo" {} {})
            (mkAsgs "eu-central-1" 1 "t3a.small" 100 "test" "test" {} {})
            (mkAsgs "us-east-2" 1 "t3a.small" 100 "test" "test" {} {})
            (mkAsgs "eu-west-1" 1 "t3a.small" 100 "test" "test" {} {})
          ]
          (args: let
            attrs =
              {
                desiredCapacity = 1;
                instanceType = "t3a.large";
                associatePublicIP = true;
                maxInstanceLifetime = 0;
                iam.role = cluster.iam.roles.client;
                iam.instanceProfile.role = cluster.iam.roles.client;

                securityGroupRules = {
                  inherit (securityGroupRules) internet internal ssh;
                };
              }
              // args;
            attrs' = removeAttrs attrs ["asgSuffix"];
            suffix =
              if args ? asgSuffix
              then
                if (builtins.match "^[A-Za-z0-9]+$" args.asgSuffix) != null
                then "-${args.asgSuffix}"
                else throw "asgSuffix must regex match a string of ^[A-Za-z0-9]$"
              else "";
            asgName = "client-${attrs.region}-${
              builtins.replaceStrings ["."] ["-"] attrs.instanceType
            }${suffix}";
          in
            lib.nameValuePair asgName attrs'));

      coreNodes = {
        core-1 = {
          instanceType = "t3a.xlarge";
          privateIP = "172.16.0.10";
          subnet = cluster.vpc.subnets.core-1;
          volumeSize = 100;

          modules = [
            bitte.profiles.core
            bitte.profiles.bootstrapper
          ];

          securityGroupRules = {
            inherit (securityGroupRules) internet internal ssh;
          };
        };

        core-2 = {
          instanceType = "t3a.xlarge";
          privateIP = "172.16.1.10";
          subnet = cluster.vpc.subnets.core-2;
          volumeSize = 100;

          modules = [
            bitte.profiles.core
          ];

          securityGroupRules = {
            inherit (securityGroupRules) internet internal ssh;
          };
        };

        core-3 = {
          instanceType = "t3a.xlarge";
          privateIP = "172.16.2.10";
          subnet = cluster.vpc.subnets.core-3;
          volumeSize = 100;

          modules = [
            bitte.profiles.core
          ];

          securityGroupRules = {
            inherit (securityGroupRules) internet internal ssh;
          };
        };

        monitoring = {
          instanceType = "t3a.xlarge";
          privateIP = "172.16.0.20";
          subnet = cluster.vpc.subnets.core-1;
          volumeSize = 300;

          modules = [
            bitte.profiles.monitoring

            # For fast oci build iteration
            (bitte + "/profiles/auxiliaries/docker.nix")
            ({
              etcEncrypted,
              dockerAuth,
              ...
            }: {
              secrets.install.docker-login = {
                source = "${etcEncrypted}/docker-passwords.json";
                target = dockerAuth;
              };
            })
          ];

          securityGroupRules = {
            inherit
              (securityGroupRules)
              internet
              internal
              ssh
              http
              https
              ;
          };
        };

        routing = {
          instanceType = "t3a.small";
          privateIP = "172.16.1.20";
          subnet = cluster.vpc.subnets.core-2;
          volumeSize = 100;
          route53.domains = ["*.${cluster.domain}"];

          modules = [
            bitte.profiles.routing

            # Required temporarily because bitte-cells.tempo.hydrationProfile qualifies
            # routing machine nixosProfile inclusion on infraType = "aws", and this is
            # an infraType "awsExt" experimental cluster.
            tempo.nixosProfiles.routing
          ];

          securityGroupRules = {
            inherit (securityGroupRules) internet internal ssh http https routing;
          };
        };

        zt = {
          instanceType = "t3a.small";
          privateIP = "172.16.0.30";
          subnet = cluster.vpc.subnets.core-1;
          volumeSize = 100;
          route53.domains = ["zt.${cluster.domain}"];
          sourceDestCheck = false;

          modules = [
            inputs.bitte.profiles.common
            inputs.bitte.profiles.consul-common
            inputs.bitte.profiles.vault-cache
            openziti.nixosModules.ziti-controller
            openziti.nixosModules.ziti-router
            openziti.nixosModules.ziti-console
            openziti.nixosModules.ziti-edge-tunnel
            ./ziti-register.nix
            ({
              config,
              pkgs,
              ...
            }: {
              boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true;

              services = {
                ziti-controller = {
                  enable = true;
                  extraBootstrapPost = ''
                    ziti edge create config \
                      vpn-host.v1 \
                      host.v1 \
                      '{"allowedAddresses":["172.16.0.0/16"],"allowedPortRanges":[{"high":65535,"low":1}],"allowedProtocols":["tcp","udp"],"forwardAddress":true,"forwardPort":true,"forwardProtocol":true}'

                    ziti edge create config \
                      vpn-intercept.v1 \
                      intercept.v1 \
                      '{"addresses":["172.16.0.0/16"],"dialOptions":{"connectTimeoutSeconds":15,"identity":""},"portRanges":[{"high":65535,"low":1}],"protocols":["tcp","udp"],"sourceIp":""}'

                    # Create service
                    ziti edge create service vpn --configs vpn-host.v1 --configs vpn-intercept.v1 --encryption ON --role-attributes vpn

                    # Create service policy
                    ziti edge create service-policy vpn-dial Dial --identity-roles '#vpn-users' --service-roles '@vpn'
                    ziti edge create service-policy vpn-bind Bind --identity-roles '#gw' --service-roles '@vpn'
                  '';
                };

                ziti-router = {
                  enable = true;
                  extraBootstrapPost = ''
                    ziti edge update identity "$EXTERNAL_DNS" --role-attributes 'gw'
                  '';
                };

                ziti-console.enable = true;
                ziti-edge-tunnel.enable = true;
              };
            })
          ];

          securityGroupRules = {
            inherit
              (securityGroupRules)
              internal
              internet
              ssh
              ziti-controller-rest
              ziti-controller-mgmt
              ziti-router-edge
              ziti-router-fabric
              ;
            # inherit
            #   (import ./sg.nix {inherit terralib lib;} config)
            #   ;
          };
        };
      };

      awsExtNodes = let
        # For each new machine provisioning to equinix:
        #   1) TF plan/apply in the `equinix` workspace to get the initial machine provisioning done
        #   2) Record the privateIP attr that the machine is assigned in the nix metal code
        #   3) Add the provisioned machine to ssh config for deploy-rs to utilize
        #   4) Update the encrypted ssh config file with the new machine so others can easily pull the ssh config
        #   5) Pull the /etc/nixos files from the provisioned machine and apply as a machine module
        #   6) Deploy again with proper private ip, provisioning configuration and bitte stack modules applied
        #
        #   TODO:
        #     - Streamline and automate the above manual workflow
        #     - ZFS client services (only assume aws clients, not awsExt clients are ZFS)
        #
        deployType = "awsExt";
        node_class = "equinix";
        primaryInterface = "bond0";
        project = "benchmarking";
        role = "client";

        awsExtCredsAttrs = {
          AWS_CONFIG_FILE = "/etc/aws/config";
          AWS_SHARED_CREDENTIALS_FILE = "/etc/aws/credentials";
        };

        awsExtCredsShell = ''
          export AWS_CONFIG_FILE="/etc/aws/config"
          export AWS_SHARED_CREDENTIALS_FILE="/etc/aws/credentials"
        '';

        baseEquinixMachineConfig = machineName: ./equinix/${machineName}/configuration.nix;

        baseEquinixModuleConfig = [
          (bitte + /profiles/client.nix)
          openziti.nixosModules.ziti-edge-tunnel
          ({
            pkgs,
            lib,
            config,
            ...
          }: {
            # Required due to Equinix networkd default and wireless dhcp default
            networking.useDHCP = false;

            services.consul = {
              # Equinix has both public and private IP bound to the bond0 primary interface and consul
              # will otherwise choose the public interface to adverstise on without this modification.
              advertiseAddr = lib.mkForce ''{{ GetPrivateInterfaces | include "network" "10.12.100.0/25" | attr "address" }}'';
              bindAddr = lib.mkForce ''{{ GetPrivateInterfaces | include "network" "10.12.100.0/25" | attr "address" }}'';
            };

            # Get sops working in systemd awsExt
            secrets.install = {
              certs.preScript = awsExtCredsShell;
              consul-server.preScript = awsExtCredsShell;
              github.preScript = awsExtCredsShell;
              nomad-server.preScript = awsExtCredsShell;
            };

            # Get vault-agent working in systemd awsExt
            systemd.services = {
              consul.environment = awsExtCredsAttrs;
              vault-agent.environment = awsExtCredsAttrs;
              promtail.environment = awsExtCredsAttrs;
              systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
            };

            services.ziti-edge-tunnel.enable = true;

            services.resolved = {
              # Vault agent does not seem to recognize successful lookups while resolved is in dnssec allow-downgrade mode
              dnssec = "false";

              # Ensure dnsmasq stays as the primary resolver while resolved is in use
              extraConfig = "Domains=~.";
            };

            # Extra prem diagnostic utils
            environment.systemPackages = with pkgs; [
              conntrack-tools
              ethtool
              icdiff
              iptstate
              tshark
            ];

            networking.firewall = {
              # Equinix machines typically have only two physically connected NICs which are bonded for throughput and HA.
              # Both public and private IP get assigned to bond0 and therefore we can't open ports to only the private IP interface
              # without also opening to the public interface using the pre-canned firewall nixos options.  So, we'll clear
              # the standard client port openings (other than ssh) and re-declare them open for only the private IP.
              allowedTCPPorts = lib.mkForce [22];
              allowedTCPPortRanges = lib.mkForce [];
              allowedUDPPorts = lib.mkForce [];
              extraCommands = ''
                # Accept connections to the allowed TCP ports at the private IP.
                iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 4646 -j nixos-fw-accept
                iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 4647 -j nixos-fw-accept
                iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 8300 -j nixos-fw-accept
                iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 8301 -j nixos-fw-accept
                iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 8302 -j nixos-fw-accept
                iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 8501 -j nixos-fw-accept
                iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 8502 -j nixos-fw-accept

                # Accept connections to the allowed TCP port ranges at the private IP.
                iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 22000:32000 -j nixos-fw-accept
                iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 21000:21255 -j nixos-fw-accept
                iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 21500:21755 -j nixos-fw-accept

                # Accept packets on the allowed UDP ports at the private IP.
                iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p udp --dport 8301 -j nixos-fw-accept
                iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p udp --dport 8302 -j nixos-fw-accept
              '';
            };
          })
        ];
      in {
        # For this PoC, turn each equinix instance into a ZTHA client connecting to a bidirectional AWS ZTNA gateway service
        test = {
          inherit deployType node_class primaryInterface role;
          equinix.project = project;
          privateIP = "10.12.100.1";

          modules = baseEquinixModuleConfig ++ [(baseEquinixMachineConfig "test")];
        };

        test2 = {
          inherit deployType node_class primaryInterface role;
          equinix.project = project;
          privateIP = "10.12.100.3";

          modules = baseEquinixModuleConfig ++ [(baseEquinixMachineConfig "test2")];
        };
      };
    };
  };
}
