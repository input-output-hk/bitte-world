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
          {
            # Extends ziti DNS over CGNAT block
            gatewayCoreNodeName = "zt";
            cidrRange = "100.64.0.0/16";
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
              ++ lib.optional (opts ? withPatroni && opts.withPatroni == true) (patroni.nixosProfiles.client node_class)
              ++ lib.optional (node_class == "test")
              ({
                lib,
                bittelib,
                ...
              }: {
                services.nomad.client.host_volume.host-nix-mount = {
                  path = "/nix";
                  read_only = false;
                };

                # Remove when ZFS >= 2.1.5
                # Ref:
                #   https://github.com/openzfs/zfs/pull/12746
                system.activationScripts.zfsAccurateHoleReporting = {
                  text = ''
                    echo 1 > /sys/module/zfs/parameters/zfs_dmu_offset_next_sync
                  '';
                  deps = [];
                };
              });
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
            (mkAsgs "eu-central-1" 2 "t3a.medium" 100 "infra" "infra" {withPatroni = true;} {})
            # (mkAsgs "eu-central-1" 1 "t3a.small" 100 "test" "test" {} {})
            # (mkAsgs "us-east-2" 1 "t3a.small" 100 "test" "test" {} {})
            # (mkAsgs "eu-west-1" 1 "t3a.small" 100 "test" "test" {} {})
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
          instanceType = "t3a.medium";
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
          instanceType = "t3a.medium";
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
          instanceType = "t3a.medium";
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
          instanceType = "t3a.medium";
          privateIP = "172.16.0.20";
          subnet = cluster.vpc.subnets.core-1;
          volumeSize = 300;

          modules = [
            bitte.profiles.monitoring

            # For fast oci build iteration
            (bitte + "/profiles/auxiliaries/docker.nix")
            ({
              nodeName,
              etcEncrypted,
              dockerAuth,
              ...
            }: {
              secrets.install.docker-login = {
                source = "${etcEncrypted}/docker-passwords.json";
                target = dockerAuth;
              };

              # Allow dnsmasq to resolve upstream ziti queries for ziti cluster DNS resolution
              services.dnsmasq.extraConfig = ''
                server=/ziti/${
                  if nodeName == "zt"
                  then "100.64.0.2"
                  else cluster.coreNodes.zt.privateIP
                }
              '';

              services.prometheus.exporters.blackbox = lib.mkForce {
                enable = true;
                configFile = pkgs.toPrettyJSON "blackbox-exporter.yaml" {
                  modules = {
                    ssh_banner = {
                      prober = "tcp";
                      timeout = "10s";
                      tcp = {
                        preferred_ip_protocol = "ip4";
                        query_response = [
                          {
                            expect = "^SSH-2.0-";
                            send = "SSH-2.0-blackbox-ssh-check";
                          }
                        ];
                      };
                    };
                  };
                };
              };

              services.vmagent.promscrapeConfig = let
                mkTarget = host: port: machine: {
                  targets = ["${host}:${toString port}"];
                  labels.alias = machine;
                };
              in [
                {
                  job_name = "blackbox-ssh-darwin";
                  scrape_interval = "60s";
                  metrics_path = "/probe";
                  params.module = ["ssh_banner"];
                  static_configs = [
                    (mkTarget "mm3.mmfarm.bitte-world.ziti" 22 "mm3-host")
                    (mkTarget "mm4.mmfarm.bitte-world.ziti" 22 "mm4-host")
                    (mkTarget "mm-arm1.mmfarm.bitte-world.ziti" 22 "mm-arm1-host")
                    (mkTarget "mm-arm2.mmfarm.bitte-world.ziti" 22 "mm-arm2-host")
                  ];
                  relabel_configs = [
                    {
                      source_labels = ["__address__"];
                      target_label = "__param_target";
                    }
                    {
                      source_labels = ["__param_target"];
                      target_label = "instance";
                    }
                    {
                      replacement = "127.0.0.1:9115";
                      target_label = "__address__";
                    }
                  ];
                }
                {
                  job_name = "mmfarm-hosts";
                  scrape_interval = "60s";
                  metrics_path = "/metrics";
                  static_configs = [
                    (mkTarget "mm3.mmfarm.bitte-world.ziti" 9100 "mm3-host")
                    (mkTarget "mm4.mmfarm.bitte-world.ziti" 9100 "mm4-host")
                    (mkTarget "mm-arm1.mmfarm.bitte-world.ziti" 9100 "mm-arm1-host")
                    (mkTarget "mm-arm2.mmfarm.bitte-world.ziti" 9100 "mm-arm2-host")
                  ];
                }
              ];
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

        zt = let
          privateIP = "172.16.0.30";
        in {
          inherit privateIP;
          instanceType = "t3a.small";
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
              nodeName,
              pkgs,
              etcEncrypted,
              ...
            }: {
              boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true;

              # Allow dnsmasq to resolve upstream ziti queries for ziti cluster DNS resolution
              services.dnsmasq.extraConfig = ''
                server=/ziti/${
                  if nodeName == "zt"
                  then "100.64.0.2"
                  else cluster.coreNodes.zt.privateIP
                }
              '';

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

                ziti-edge-tunnel = {
                  enable = true;
                  dnsUpstream = null;
                };

                ziti-console.enable = true;
              };

              networking = {
                firewall.allowedUDPPorts = [51820];
                wireguard = {
                  enable = true;
                  interfaces.wg-zt = {
                    listenPort = 51820;
                    ips = ["10.10.0.254/32"];
                    privateKeyFile = "/etc/wireguard/private.key";
                    peers = [
                      # mm3
                      {
                        publicKey = "SCNSJqSbmNpJpucOdqCDabZy1+It/9yEpds50KEjRyc=";
                        allowedIPs = ["10.10.0.3/32" "10.10.0.103/32"];
                        persistentKeepalive = 30;
                      }
                      # mm4
                      {
                        publicKey = "v9tIACN9BsUzy5dx82EW0ruFJUHmyLyTzkxLA5dCbiI=";
                        allowedIPs = ["10.10.0.4/32" "10.10.0.104/32"];
                        persistentKeepalive = 30;
                      }
                      # mm1-arm
                      {
                        publicKey = "ud4AYflwezVBoa/4t3OL/+VWB7J4LNbMn7vtMEsKXgU=";
                        allowedIPs = ["10.10.0.51/32" "10.10.0.151/32"];
                        persistentKeepalive = 30;
                      }
                      # mm2-arm
                      {
                        publicKey = "u3pneYtAowgYoPESBO0OsjNfyb1nEl+r6CoODoc5jHE=";
                        allowedIPs = ["10.10.0.52/32" "10.10.0.152/32"];
                        persistentKeepalive = 30;
                      }
                    ];
                  };
                };
              };

              secrets.install.zt-wg-private = {
                source = "${etcEncrypted}/zt-wg-private";
                target = "/etc/wireguard/private.key";
                outputType = "binary";
                script = ''
                  chmod 0400 /etc/wireguard/private.key
                '';
              };

              secrets.install.zt-wg-public = {
                source = "${etcEncrypted}/zt-wg-public";
                target = "/etc/wireguard/public.key";
                outputType = "binary";
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
            inherit
              (import ./sg.nix {inherit terralib lib;} config)
              wg
              ;
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
        role = "client";

        # Equinix TF specific attrs
        plan = "c3.small.x86";
        project = "benchmarking";

        baseEquinixMachineConfig = machineName: ./equinix/${machineName}/configuration.nix;

        baseEquinixModuleConfig = [
          (bitte + /profiles/client.nix)
          (bitte + /profiles/multicloud/aws-extended.nix)
          (bitte + /profiles/multicloud/equinix.nix)
          openziti.nixosModules.ziti-edge-tunnel
          ({
            pkgs,
            lib,
            config,
            ...
          }: {
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
          })
        ];
      in {
        # For this PoC, turn each equinix instance into a ZTHA client connecting to a bidirectional AWS ZTNA gateway service
        # test = {
        #   inherit deployType node_class primaryInterface role;
        #   equinix = {inherit plan project;};
        #   privateIP = "10.12.100.1";

        #   modules = baseEquinixModuleConfig ++ [(baseEquinixMachineConfig "test")] ++ [
        #    ({pkgs, self, ...}: let
        #      inherit (self.inputs.nixpkgs-nix.legacyPackages.x86_64-linux.nixVersions) nix_2_12;
        #    in {
        #      nix.package = nix_2_12;
        #      environment.systemPackages = [nix_2_12];
        #    })
        #   ];
        # };

        # test2 = {
        #   inherit deployType node_class primaryInterface role;
        #   equinix.project = project;
        #   privateIP = "10.12.100.3";

        #   modules = baseEquinixModuleConfig ++ [(baseEquinixMachineConfig "test2")];
        # };
      };
    };
  };
}
