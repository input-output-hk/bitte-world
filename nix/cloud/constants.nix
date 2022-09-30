{
  inputs,
  cell,
}: let
  # Metadata
  # -----------------------------------------------------------------------
  baseDomain = "bitte.aws.iohkdev.io";
in rec {
  # App Component Import Parameterization
  # -----------------------------------------------------------------------
  args = {
    patroni = {
      namespace = "patroni";
      domain = "${baseDomain}";
      nodeClass = "patroni";
      datacenters = ["eu-central-1"];
    };

    tempo = {
      namespace = "tempo";
      domain = "${baseDomain}";
      nodeClass = "tempo";
      datacenters = ["eu-central-1"];
    };
  };

  patroni = let
    inherit (args.patroni) namespace;
  in rec {
    # App constants
    WALG_S3_PREFIX = "s3://iohk-bitte-world/backups/${namespace}/walg";

    # Job mod constants
    patroniMods.scaling = 3;
    patroniMods.resources.cpu = 2000;
    patroniMods.resources.memory = 2 * 1024;
  };

  tempo = let
    inherit (args.tempo) namespace;
  in rec {
    # Job mod constants
    tempoMods.scaling = 1;
    tempoMods.resources.cpu = 2000;
    tempoMods.resources.memory = 2 * 1024;
    tempoMods.storageS3Bucket = "iohk-bitte-world-tempo";
    tempoMods.storageS3Endpoint = "s3.eu-central-1.amazonaws.com";
  };
}
