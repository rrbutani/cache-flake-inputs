# `cache-flake-inputs`

Premise:
  - You have a large or otherwise inconvenient-to-fetch (i.e. requires auth) **non-flake** flake input.
  - You cannot switch to using a fetcher to grab this input instead for Reasons (i.e. requires auth).
  - You provide a remote cache for users of your flake that contains binaries for all of your flake outputs.
  - You would like for users of your flake to not need to fetch your large flake input themselves and to instead just fetch artifacts from your remote cache.

The problem:
  - Flake inputs [*are* fetched lazily](https://github.com/NixOS/nix/commit/6dbd5c26e6c853f302cd9d3ed171d134ff24ffe1) (once locking has happened)
  - But: in order to actually produce the derivation (which is then substituted and *not* built locally) for any of this flake's outputs, we need to, at eval time, reference our flake's inputs. The moment we do this, the flake input is fetched, even though we may never actually use the contents of the flake's nix store path.

Eventually we can maybe use [`fetch-closure` (experimental)](https://nixos.org/manual/nix/stable/expressions/builtins.html#builtins-fetchClosure) for this use case but in the meantime...

This flake provides an expression that conditionally replaces flake inputs with fixed output derivations that are assumed to be accessible to the user of the flake (i.e. because they are in a substituter that comes with the
flake).

## example

```nix
{
  nixConfig = {
    # A remote cache that you provide.
    extra-substituters = [
      "https://rrbutani.cachix.org"
    ];
    extra-trusted-public-keys = [
      "rrbutani.cachix.org-1:FUpcK9RyZjjdOm8qherJl9+wfTGf6ptANvH6LZF63Ro="
    ];
  };

  inputs = {
    # A large unwieldy flake input (an example).
    llvm = {
      url = github:llvm/llvm-project?ref=llvmorg-14.0.6;
      flake = false;
    };

    flu.url = github:numtide/flake-utils;
    nixpkgs.url = github:nixOS/nixpkgs/22.05;

    cfi-override.url = github:boolean-option/true;
    cfi = {
      url = github:rrbutani/cache-flake-inputs;

      # You can set this to `false` to disable `cacheInputs`.
      #
      # This is useful for changing the behavior of your _transitive_ flake dependencies.
      inputs.cache-flake-inputs-global-override.follows = "cfi-override";
    };
  };

  outputs = inputs@{ flu, cfi, nixpkgs, ... }: with flu.lib; eachDefaultSystem (sys: let
    knownCachedNarHashes = {
      # Keys should match the names of your flake inputs.
      "llvm" = {
        # Hashes should match what's in your `flake.lock`.
        "sha256-vffu4HilvYwtzwgq+NlS26m65DGbp6OSSne2aje1yJE=" = true;
      };
    };

    np = import nixpkgs { system = sys; };
    inputs' = cfi.lib.${sys}.cacheInputs {
      inherit inputs knownCachedNarHashes;
      lockFile = ./flake.lock;

      # This tells `cfi` to assume that we can indeed use substituters to get the
      # things `knownCachedNarHashes` says we can.
      #
      # If this is set to `false`, `cfi` will effectively do nothing; derivations
      # in `inputs'` will be equivalent to the ones in `inputs` and flake inputs
      # will be fetched eagerly during evaluation.
      useSubstituters = true;

      # We already have a `nixpkgs` instance so pass it along.
      #
      # This is optional; if omitted, `cfi` will use it's own `nixpkgs` flake
      # input — which you can override with `inputs.cfi.inputs.nixpkgs.follows`).
      nixpkgs = np;
    };

    pkgC = src: np.stdenvNoCC.mkDerivation {
      name = "example";
      src = src;
      unpackPhase = "true";
      installPhase = ''
        cat $src/libunwind/CMakeLists.txt | grep PACKAGE_VERSION | cut -d' ' -f4- | cut -d')' -f1 | head -1 > $out
      '';
    };

    # Both `pkgA` and `pkgB` are in the substituter listed at the top of this flake.

    # Building `pkgA` will require fetching LLVM.
    pkgA = pkgC inputs.llvm;

    # Building `pkgB` will not.
    pkgB = pkgC inputs'.llvm;
  in {
    packages = {
      default = pkgB;
      inherit pkgA pkgB;
    };
  });
}
```

(available with a flake.lock [here](https://gist.github.com/rrbutani/474ec08b6b5f3389c39ed7fd3ff4dc13))
