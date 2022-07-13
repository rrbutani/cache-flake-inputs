{
  inputs.nixpkgs.url = github:nixOS/nixpkgs/22.05;
  inputs.flu.url = github:numtide/flake-utils;

  outputs = { self, nixpkgs }: with flu.lib; let
    lib = { cacheInputs = import ./cacheInputs; };
    forEachSystem = sys: {
      cacheInputs = attrs: lib.cacheInputs ({ nixpkgs = import nixpkgs { system = sys; }; }) // attrs;
    };
  in
    lib // (forEachDefaultSystem forEachSystem);
}
