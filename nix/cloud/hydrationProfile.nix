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
      (bitte-cells.patroni.hydrationProfiles.hydrate-cluster ["testnet"])
    ];

    # NixOS-level hydration
    # --------------

    cluster = {
      name = "bitte-world";

      adminNames = ["john.lotoski"];
      developerGithubNames = [];
      developerGithubTeamNames = [];
      domain = "bitte.aws.iohkdev.io";
      kms = "arn:aws:kms:eu-central-1:415292740809:key/ac0f6066-1359-4fbc-899b-922f0b34492e";
      s3Bucket = "iohk-bitte-world";
      s3Tempo = "iohk-bitte-world-tempo";
    };

    services = {
      nomad.namespaces = {
        testnet = {description = "Bitte testnet";};
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

          client.path = caps {
            "auth/token/create" = [u s];
            "auth/token/create/nomad-cluster" = [u];
            "auth/token/create/nomad-server" = [u];
            "auth/token/lookup" = [u];
            "auth/token/lookup-self" = [r];
            "auth/token/renew-self" = [u];
            "auth/token/revoke-accessor" = [u];
            "auth/token/roles/nomad-cluster" = [r];
            "auth/token/roles/nomad-server" = [r];
            "consul/creds/consul-agent" = [r];
            "consul/creds/consul-default" = [r];
            "consul/creds/consul-register" = [r];
            "consul/creds/nomad-client" = [r];
            "consul/creds/vault-client" = [r];
            "kv/data/bootstrap/clients/*" = [r];
            "kv/data/bootstrap/static-tokens/clients/*" = [r];
            "kv/data/nomad-cluster/*" = [r l];
            "kv/metadata/nomad-cluster/*" = [r l];
            "nomad/creds/nomad-follower" = [r u];
            "pki/issue/client" = [c u];
            "pki/roles/client" = [r];
            "sys/capabilities-self" = [u];
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
            node.policy = "read";
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

          # inherit
          #   (inputs.bitte-cells.tempo.alerts)
          #   bitte-cells-tempo
          #   ;
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

          # inherit
          #   (inputs.bitte-cells.tempo.dashboards)
          #   bitte-cells-tempo
          #   ;
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
