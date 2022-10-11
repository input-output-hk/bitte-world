{
  inputs,
  cell,
}: let
  inherit
    (inputs)
    self
    nixpkgs
    ;
  inherit (inputs.cells) openziti;
in {
  ziti-cli-functions = nixpkgs.writeShellApplication {
    runtimeInputs = with nixpkgs; [coreutils curl hostname jq killall openssl];
    name = "ziti-cli-functions.sh";
    text = builtins.readFile ./scripts/ziti-cli-functions.sh;
  };
}
