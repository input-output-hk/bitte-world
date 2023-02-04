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
    infra = {
      namespace = "infra";
      domain = "${baseDomain}";
      nodeClass = "infra";
      datacenters = ["eu-central-1"];
    };
  };

  infra = let
    inherit (args.infra) namespace;
  in rec {
    # App constants
    WALG_S3_PREFIX = "s3://iohk-bitte-world/backups/${namespace}/walg";

    # Job mod constants
    patroniMods.scaling = 2;
    patroniMods.pkiTtl = "3600s";
    patroniMods.resources.cpu = 1000;
    patroniMods.resources.memory = 1 * 1024;

    tempoMods.scaling = 1;
    tempoMods.resources.cpu = 1000;
    tempoMods.resources.memory = 1 * 1024;
    tempoMods.storageS3Bucket = "iohk-bitte-world-tempo";
    tempoMods.storageS3Endpoint = "s3.eu-central-1.amazonaws.com";
  };
}
