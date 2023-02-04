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
      (bitte-cells.patroni.hydrationProfiles.hydrate-cluster ["infra"])
      (bitte-cells.tempo.hydrationProfiles.hydrate-cluster ["infra"])
    ];

    # NixOS-level hydration
    # --------------

    cluster = {
      name = "bitte-world";
      infraType = "awsExt";

      adminNames = ["john.lotoski"];
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
        infra = {description = "infra";};
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
            (inputs.bitte-cells.tempo.alerts)
            bitte-cells-tempo
            ;

           # Modified bitte-cells-patroni alerts due to running a 2 member cluster
           bitte-cells-patroni-modified = {
             datasource = "vm";
             rules = [
               {
                 alert = "PatroniClusterUnlocked";
                 expr = "patroni_cluster_unlocked > 0";
                 for = "5m";
                 labels.severity = "critical";
                 annotations = {
                   description = ''
                     Patroni cluster has been unlocked in namespace {{ $labels.namespace }} on allocation {{ $labels.nomad_alloc_name }} for more than 5 minutes.'';
                   summary = "[Bitte-cells] Patroni cluster is unlocked in namespace {{ $labels.namespace }} on allocation {{ $labels.nomad_alloc_name }}";
                 };
               }
               {
                 alert = "PatroniDcsMissing";
                 expr = "rate(patroni_dcs_last_seen)[1m] == 0";
                 for = "5m";
                 labels.severity = "critical";
                 annotations = {
                   description = ''
                     Patroni cluster has not checked in with the DCS in namespace {{ $labels.namespace }} on allocation {{ $labels.nomad_alloc_name }} for more than 5 minutes.'';
                   summary = "[Bitte-cells] Patroni cluster has not checked in with the DCS in namespace {{ $labels.namespace }} on allocation {{ $labels.nomad_alloc_name }}";
                 };
               }
               {
                 alert = "PatroniLeaderMissing";
                 expr = "sum by (namespace) (patroni_master) < 1";
                 for = "5m";
                 labels.severity = "critical";
                 annotations = {
                   description = ''
                     Patroni cluster in namespace {{ $labels.namespace }} has had no leader running for more than 5 minutes.'';
                   summary = "[Bitte-cells] Patroni cluster in namespace {{ $labels.namespace }} has no leader running";
                 };
               }
               {
                 alert = "PatroniMemberMissing";
                 expr = "sum by (namespace) (patroni_postgres_running) < 2";
                 for = "5m";
                 labels.severity = "critical";
                 annotations = {
                   description = ''
                     Patroni cluster in namespace {{ $labels.namespace }} has had only {{ $value }} member(s) running for more than 5 minutes.'';
                   summary = "[Bitte-cells] Patroni cluster in namespace {{ $labels.namespace }} has less than three members running";
                 };
               }
               {
                 alert = "PatroniReplicaMissing";
                 expr = "sum by (namespace) (patroni_replica) == 0";
                 for = "5m";
                 labels.severity = "critical";
                 annotations = {
                   description = ''
                     Patroni cluster in namespace {{ $labels.namespace }} has had no replicas available for more than 5 minutes.'';
                   summary = "[Bitte-cells] Patroni cluster in namespace {{ $labels.namespace }} has no replicas available";
                 };
               }
               {
                 alert = "PatroniTimelineMismatch";
                 expr = "stddev by (scope) (patroni_postgres_timeline) > 0";
                 for = "1h";
                 labels.severity = "critical";
                 annotations = {
                   description = ''
                     One or more patroni postgres {{ $labels.scope }} members have not joined the latest timeline for more than 1 hour in namespace {{ $labels.namespace }}.
                      This likely indicates some member(s) need manual intervention to catch up with the leader.'';
                   summary = "[Bitte-cells] Patroni member(s) have not joined the latest timeline in namespace {{ $labels.namespace }} for more than 1 hour";
                 };
               }
               {
                 alert = "PatroniTimelineIncreasing";
                 expr = "sum_over_time(rate(patroni_postgres_timeline)[1h]) > 2";
                 for = "5m";
                 labels.severity = "critical";
                 annotations = {
                   description = ''
                     The patroni postgres timeline has increased by an average of {{ $value }} timelines
                      over the past hour in namespace {{ $labels.namespace }} on allocation {{ $labels.nomad_alloc_name }}.'';
                   summary = "[Bitte-cells] Patroni timeline is increasing rapidly in namespace {{ $labels.namespace }} on allocation {{ $labels.nomad_alloc_name }}";
                 };
               }
               {
                 alert = "PatroniXlogPaused";
                 expr = "patroni_xlog_paused > 0";
                 for = "5m";
                 labels.severity = "critical";
                 annotations = {
                   description = ''
                     Patroni cluster has an xlog paused in namespace {{ $labels.namespace }} on allocation {{ $labels.nomad_alloc_name }} for more than 5 minutes.'';
                   summary = "[Bitte-cells] Patroni cluster has an xlog paused in namespace {{ $labels.namespace }} on allocation {{ $labels.nomad_alloc_name }}";
                 };
               }
             ];
           };
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
