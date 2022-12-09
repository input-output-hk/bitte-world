inputs: final: prev: rec {
  zfs = prev.zfs.overrideAttrs (old: {
    name = "zfs-user-2.1.7";
    src = prev.fetchFromGitHub {
      owner = "openzfs";
      repo = "zfs";
      rev = "zfs-2.1.7";
      sha256 = "sha256-vLm6RE11nqOCoYXne79JU3nUQnVEUNbwrULwFfghWcI=";
    };
  });
}
