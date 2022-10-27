{
  inputs,
  cell,
}: let
  inherit (inputs) capsules bitte-cells bitte deploy-rs nixpkgs;
  inherit (inputs.std) std;
  inherit (inputs.std.lib) dev;

  # FIXME: this is a work around just to get access
  # to 'awsAutoScalingGroups'
  # TODO: std ize bitte properly to make this interface nicer
  bitte-world' = inputs.bitte.lib.mkBitteStack {
    inherit inputs;
    inherit (inputs) self;
    domain = "bitte.aws.iohkdev.io";
    bitteProfile = inputs.cells.metal.bitteProfile.default;
    hydrationProfile = inputs.cells.cloud.hydrationProfile.default;
    deploySshKey = "not-a-key";
  };

  bitteWorld = {
    extraModulesPath,
    pkgs,
    ...
  }: {
    name = nixpkgs.lib.mkForce "Bitte World";
    imports = [
      std.devshellProfiles.default
      bitte.devshellModule
    ];
    bitte = {
      domain = "bitte.aws.iohkdev.io";
      cluster = "bitte-world";
      namespace = "testnet";
      provider = "AWS";
      cert = null;
      aws_profile = "bitte-world";
      aws_region = "eu-central-1";
      aws_autoscaling_groups =
        bitte-world'.clusters.bitte-world._proto.config.cluster.awsAutoScalingGroups;
    };
  };
in {
  dev = dev.mkShell {
    imports = [
      bitteWorld
      capsules.base
      capsules.cloud
    ];
  };
  ops = dev.mkShell {
    imports = [
      bitteWorld
      capsules.base
      capsules.cloud
      capsules.hooks
      capsules.metal
      capsules.integrations
      capsules.tools
      bitte-cells.patroni.devshellProfiles.default
    ];
    commands = let
      withCategory = category: attrset: attrset // {inherit category;};
      bitteWorld = withCategory "bitte-world";
    in
      with nixpkgs; [
        (bitteWorld {package = deploy-rs.defaultPackage;})
        (bitteWorld {package = httpie;})
      ];
  };
}
