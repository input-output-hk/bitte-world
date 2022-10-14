{
  terralib,
  lib,
}: config: let
  inherit (terralib) cidrsOf;
  inherit (config.cluster.vpc) subnets;
  awsAsgVpcs = terralib.aws.asgVpcs config.cluster;

  global = ["0.0.0.0/0"];
  internal = [config.cluster.vpc.cidr] ++ (lib.forEach awsAsgVpcs (vpc: vpc.cidr));
in {
  ziti-controller-rest = {
    port = 1280;
    protocols = ["tcp"];
    cidrs = global;
  };

  ziti-controller-mgmt = {
    port = 6262;
    protocols = ["tcp"];
    cidrs = global;
  };

  ziti-router-edge = {
    port = 3022;
    protocols = ["tcp"];
    cidrs = global;
  };

  ziti-router-fabric = {
    port = 10080;
    protocols = ["tcp"];
    cidrs = global;
  };
}
