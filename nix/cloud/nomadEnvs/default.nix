{
  inputs,
  cell,
}: let
  inherit (inputs.data-merge) append merge update;
  inherit (inputs.bitte-cells) patroni tempo vector;
  inherit (cell) constants;
  inherit (constants) args;
  inherit (cell.library) pp;
in {
  patroni = let
    inherit
      (constants.patroni)
      # App constants
      
      WALG_S3_PREFIX
      # Job mod constants
      
      patroniMods
      ;
  in {
    database = merge (patroni.nomadCharts.default (args.patroni // {inherit (patroniMods) scaling;})) {
      job.database.constraint = append [
        {
          operator = "distinct_property";
          attribute = "\${attr.platform.aws.placement.availability-zone}";
        }
      ];
      job.database.group.database.task.patroni.resources = {inherit (patroniMods.resources) cpu memory;};
      job.database.group.database.task.patroni.env = {inherit WALG_S3_PREFIX;};
      job.database.group.database.task.backup-walg.env = {inherit WALG_S3_PREFIX;};
    };
  };

  tempo = let
    inherit
      (constants.tempo)
      # App constants
      
      WALG_S3_PREFIX
      # Job mod constants
      
      tempoMods
      ;
  in {
    tempo = merge (tempo.nomadCharts.default (args.tempo
      // {
        inherit (tempoMods) scaling;
        extraTempo = {
          services.tempo = {
            inherit (tempoMods) storageS3Bucket storageS3Endpoint;
          };
        };
      })) {
      job.tempo.group.tempo.task.tempo = {
        env = {
          # DEBUG_SLEEP = 3600;
          # LOG_LEVEL = "debug";
        };
        # To use slightly less resources than the tempo default:
        resources = {inherit (tempoMods.resources) cpu memory;};
      };
    };
  };
}
