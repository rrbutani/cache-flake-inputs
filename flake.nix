{
  description = "Explicit substitution for non-flake flake inputs.";

  inputs.nixpkgs.url = github:nixOS/nixpkgs/22.05;
  inputs.flu.url = github:numtide/flake-utils;

  # We accept any input that either contains a `true` or `false` file or
  # contains a single file containing `true` or `false`.
  inputs.cache-flake-inputs-global-override = {
    # If you're on nix 2.9 or newer you can specify single files instead, like:
    # `url = "https://raw.githubusercontent.com/boolean-option/true/main/true"`
    # `url = "https://raw.githubusercontent.com/boolean-option/false/main/false"`
    #
    # See:
    #   - https://github.com/NixOS/nix/issues/5979
    #   - https://github.com/NixOS/nix/pull/6548
    url = github:boolean-option/true;
    flake = false;
  };

  outputs = { self, nixpkgs, flu, cache-flake-inputs-global-override }: with flu.lib; let
    globalOverride = let
      setting = cache-flake-inputs-global-override;
      trueFile = builtins.pathExists "${setting}/true";
      falseFile = builtins.pathExists "${setting}/false";

      # Assuming it's a single file if it's not a directory containing `true` or
      # `false`.
      singleFile = builtins.readFile "${setting}";
      trueSingleFile = singleFile == "true";
      falseSingleFile = singleFile == "false";
      otherwise = builtins.abort ''
        We expect either:
          - a directory containing a file named `true` or a file named `false`
          - a single file containing the text "true" or "false"

        Consider using:
          - `github:boolean-option/true`
          - `github:boolean-option/false`
      '';
    in
      if trueFile then true else
      if falseFile then false else
      if trueSingleFile then true else
      if falseSingleFile then false else
      otherwise
    ;

    lib = { cacheInputs = import ./cacheInputs.nix globalOverride; };
    forEachSystem = sys: {
      # If `nixpkgs` is provided explicitly by the user we should never even
      # fetch our `nixpkgs` flake input.
      lib.cacheInputs = attrs: lib.cacheInputs ({ nixpkgs = import nixpkgs { system = sys; }; } // attrs);
    };
  in
    lib // (eachDefaultSystem forEachSystem);
}
