{
  description = "Explicit substitution for non-flake flake inputs.";

  inputs.nixpkgs.url = github:nixOS/nixpkgs/22.05;
  inputs.flu.url = github:numtide/flake-utils;

  # We accept a flake input that exposes `outputs.value` as a bool.
  #
  # You probably want to use:
  #   - github:boolean-option/true
  #   - github:boolean-option/false
  inputs.cache-flake-inputs-global-override.url = github:boolean-option/true;

  outputs = { self, nixpkgs, flu, cache-flake-inputs-global-override }: with flu.lib; let
    globalOverride = cache-flake-inputs-global-override.value;
    lib = { cacheInputs = import ./cacheInputs.nix globalOverride; };
    forEachSystem = sys: {
      # If `nixpkgs` is provided explicitly by the user we should never even
      # fetch our `nixpkgs` flake input.
      lib.cacheInputs = attrs: lib.cacheInputs ({ nixpkgs = import nixpkgs { system = sys; }; } // attrs);
    };
  in
    lib // (eachDefaultSystem forEachSystem);
}
