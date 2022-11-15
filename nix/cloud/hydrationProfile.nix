{
  inputs,
  cell,
}: let
  inherit (inputs) bitte-cells;
in {
  # Bitte Hydrate Module
  # -----------------------------------------------------------------------

  default = {
    lib,
    bittelib,
    ...
  }: {
    imports = [
      (bitte-cells.patroni.hydrationProfiles.hydrate-cluster ["patroni"])
      (bitte-cells.tempo.hydrationProfiles.hydrate-cluster ["tempo"])
    ];

    # NixOS-level hydration
    # --------------

    cluster = {
      name = "bitte-world";
      infraType = "awsExt";

      adminNames = ["johnalotoski"];
      # adminGithubTeamNames = lib.mkForce [ "non-existent-team" ];
      developerGithubNames = ["shlevy"];
      developerGithubTeamNames = [];
      domain = "bitte.aws.iohkdev.io";
      kms = "arn:aws:kms:eu-central-1:415292740809:key/ac0f6066-1359-4fbc-899b-922f0b34492e";
      s3Bucket = "iohk-bitte-world";
      s3Tempo = "iohk-bitte-world-tempo";
    };

    services = {
      nomad.namespaces = {
        patroni = {description = "patroni";};
        tempo = {description = "tempo";};
        test = {description = "test";};
      };
    };

    # cluster level (terraform)
    # --------------
    tf.hydrate-cluster.configuration = {
      locals.policies = {
        vault = let
          c = "create";
          r = "read";
          u = "update";
          d = "delete";
          l = "list";
          s = "sudo";
          caps = lib.mapAttrs (n: v: {capabilities = v;});
        in {
          developer.path = {
            "kv/data/test/*".capabilities = [c r u d l];
            "kv/metadata/*".capabilities = [l];
          };

          admin.path = caps {
            "secret/*" = [c r u d l];
            "auth/github-terraform/map/users/*" = [c r u d l s];
            "auth/github-employees/map/users/*" = [c r u d l s];
          };

          terraform.path = caps {
            "secret/data/vbk/*" = [c r u d l];
            "secret/metadata/vbk/*" = [d];
          };

          vit-terraform.path = caps {
            "secret/data/vbk/vit-testnet/*" = [c r u d l];
            "secret/metadata/vbk/vit-testnet/*" = [c r u d l];
          };
        };

        consul.developer = {
          service_prefix."*" = {
            policy = "write";
          };
          key_prefix."test" = {
            policy = "write";
          };
        };

        consul.patroni = {
          vaultConsulSecretBackendRole = {
            ttl = "3600";
            max_ttl = "3600";
          };
        };

        nomad = {
          admin = {
            description = "Admin policies";
            namespace."*" = {
              policy = "write";
              capabilities = [
                "alloc-exec"
                "alloc-lifecycle"
                "alloc-node-exec"
                "csi-list-volume"
                "csi-mount-volume"
                "csi-read-volume"
                "csi-register-plugin"
                "csi-write-volume"
                "dispatch-job"
                "list-jobs"
                "list-scaling-policies"
                "read-fs"
                "read-job"
                "read-job-scaling"
                "read-logs"
                "read-scaling-policy"
                "scale-job"
                "submit-job"
              ];
            };
          };

          developer = {
            description = "Dev policies";
            namespace."*".policy = "deny";
            agent.policy = "read";
            quota.policy = "read";
            node.policy = "read";
            host_volume."*".policy = "write";
            namespace."test" = {
              policy = "write";
              capabilities = [
                "submit-job"
                "dispatch-job"
                "read-logs"
                "alloc-exec"
                "alloc-node-exec"
                "alloc-lifecycle"
              ];
            };
          };
        };
      };
    };

    # Observability State
    # --------------
    tf.hydrate-monitoring.configuration = {
      resource =
        inputs.bitte-cells._utils.library.mkMonitoring
        # Alert attrset
        {
          # Organelle local declared dashboards
          # inherit
          #   (cell.alerts)
          # ;

          # Upstream alerts not having downstream deps can be directly imported here
          inherit
            (inputs.bitte-cells.bitte.alerts)
            bitte-consul
            bitte-deadmanssnitch
            bitte-loki
            bitte-system
            bitte-vault
            bitte-vm-health
            bitte-vm-standalone
            bitte-vmagent
            ;

          inherit
            (inputs.bitte-cells.patroni.alerts)
            bitte-cells-patroni
            ;

          inherit
            (inputs.bitte-cells.tempo.alerts)
            bitte-cells-tempo
            ;
        }
        # Dashboard attrset
        {
          # Organelle local declared dashboards
          # inherit
          #   (cell.dashboards)
          #   ;

          # Upstream dashboards not having downstream deps can be directly imported here
          inherit
            (inputs.bitte-cells.bitte.dashboards)
            bitte-consul
            bitte-log
            bitte-loki
            bitte-nomad
            bitte-system
            bitte-traefik
            bitte-vault
            bitte-vmagent
            bitte-vmalert
            bitte-vm
            bitte-vulnix
            ;

          inherit
            (inputs.bitte-cells.patroni.dashboards)
            bitte-cells-patroni
            ;

          inherit
            (inputs.bitte-cells.tempo.dashboards)
            bitte-cells-tempo-operational
            bitte-cells-tempo-reads
            bitte-cells-tempo-writes
            ;
        };
    };

    # application state (terraform)
    # --------------
    tf.hydrate-app.configuration = let
      vault' = {
        dir = ./. + "/kv/vault";
        prefix = "kv";
      };
      # consul' = {
      #   dir = ./. + "/kv/consul";
      #   prefix = "config";
      # };
      vault = bittelib.mkVaultResources {inherit (vault') dir prefix;};
      # consul = bittelib.mkConsulResources {inherit (consul') dir prefix;};
    in {
      data = {inherit (vault) sops_file;};
      resource = {
        inherit (vault) vault_generic_secret;
        # inherit (consul) consul_keys;
      };
    };
  };
}
