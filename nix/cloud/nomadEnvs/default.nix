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
  infra = let
    inherit
      (constants.infra)
      # App constants

      WALG_S3_PREFIX
      # Job mod constants

      patroniMods
      tempoMods
      ;
  in {
    database = merge (patroni.nomadCharts.default (args.infra // {inherit (patroniMods) scaling pkiTtl;})) {
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

    tempo = merge (tempo.nomadCharts.default (args.infra
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
