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
    testnet = {
      namespace = "testnet";
      domain = "${baseDomain}";
      nodeClass = "testnet";
      datacenters = ["eu-central-1"];
    };
  };

  prod = let
    inherit (args.prod) namespace;
  in rec {
    # App constants
    WALG_S3_PREFIX = "s3://iohk-bitte-world/backups/${namespace}/walg";

    # Job mod constants
    patroniMods.scaling = 3;
    patroniMods.resources.cpu = 12000;
    patroniMods.resources.memory = 16 * 1024;
  };
}
