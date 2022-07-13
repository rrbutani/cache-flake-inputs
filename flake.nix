{
  inputs.nixpkgs.url = github:nixOS/nixpkgs/22.05;
  inputs.flu.url = github:numtide/flake-utils;

  outputs = { self, nixpkgs, flu }: with flu.lib; let
    lib = { cacheInputs = import ./cacheInputs.nix; };
    forEachSystem = sys: {
      # If `nixpkgs` is provided explicitly by the user we should never even
      # fetch our `nixpkgs` flake input.
      lib.cacheInputs = attrs: lib.cacheInputs ({ nixpkgs = import nixpkgs { system = sys; }; } // attrs);
    };
  in
    lib // (eachDefaultSystem forEachSystem);
}
