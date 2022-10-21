globalOverride:
attrs@
{ inputs
, lockFile
, knownCachedNarHashes
, extraAttrsOnInputDrvs ? (lockNode: {})
, useSubstituters ? false
, recursiveNixAllowed ? false

# Either provide `nixpkgs` or provide the rest of these.
, nixpkgs ? null
, stdenvNoCC ? nixpkgs.stdenvNoCC
, writeScript ? nixpkgs.writeScript
, lib ? nixpkgs.lib
, nix ? nixpkgs.nix
, system ? stdenvNoCC.buildPlatform.system
}:
let
  lockFile = builtins.fromJSON (builtins.readFile attrs.lockFile);

  # Introduce a level of indirection.
  #
  # This can be either a copy of the flake input or a `requireFile`-esque
  # derivation that makes reference to a derivation already in the
  # store/substituter.
  #
  # Because this is a fixed-output derivation and not an input addressed
  # derivation, both will ultimately yield the same downstream artifacts.
  # they must match.

  # Creates a fixed-output clone of the flake input (src).
  #
  # This derivation *should* have the same output path as the flake input
  # and should never actually be built. By referencing `src` it should
  # cause it to be fetched, removing the need for this derivation to be
  # built.
  mkFixedOutputCopy = attrs@{ src, hash, ... }: stdenvNoCC.mkDerivation ({
    name = "source"; # Always set to "source" to match how flake inputs work.
    inherit src;
    builder = ''
      echo "The flake input at $src should have the same output path as this derivation!"

      exit 1
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = hash;
  } // (
    builtins.removeAttrs attrs ["name" "src" "hash"]
  ));

  # Assumes the flake input is already in the store (or in a substitute)
  # and creates a derivation that assumes it will not actually be built.
  useExistingFixedOutputDrv = attrs@{ name, hash, ... }: stdenvNoCC.mkDerivation ({
    name = "source"; # Always set to "source" to match how flake inputs work.

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = hash;
    allowSubstitutes = true;

    builder = writeScript "error" ''
      echo "This derivation (for ${name}) should always be substituted!"
      echo ""
      echo "Have you accepted this flake's `extra-substituters`?"
      echo "Are you in `trusted-users` in `/etc/nix/nix.conf` if you're running a multi-user setup?"
      echo ""
      echo "If you are not using this flake's caches, please set `useSubstituters` to `false`."

      exit 1
    '';
  } // (
    builtins.removeAttrs attrs ["name" "src" "hash"]
  ));

  # Checks if the flake input is already present locally.
  #
  # TODO: this seems to trigger errors on machines that have the sandbox
  # enabled; cannot access `/nix/var`.
  checkForFixedOutputDrvLocally = { name, hash }: let
    chk = stdenvNoCC.mkDerivation {
      name = name + "-chk";
      nativeBuildInputs = [ nix ];
      unpackPhase = "true";
      installPhase = ''
        cat <<EOF > default.nix
        derivation {
          name = "${name}";
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "${hash}";
          system = "${system}";
          builder = "error";
        }
        EOF

        outPath=$(nix eval --extra-experimental-features nix-command --expr "(import ./.).outPath" --impure)
        echo ${hash} >&2
        echo $outPath >&2

        nix-build -vvvvv --no-substitute && res=true || res=false

        echo "{ path = $outPath; present = $res; }" > $out
      '';
    };
  in
    import chk;

  # Checks if the input is either already present locally or known to be
  # present in the substituters bundled with this flake.
  checkForFixedOutputDrv = args@{ name, hash }: let
    presentLocally = if recursiveNixAllowed then
      checkForFixedOutputDrvLocally args
    else { present = false; path = "unknown"; };
    warning = lib.trivial.warn ''


      Entry for flake input `${name}` with hash `${hash}`
      is not present in the list of known cached flake inputs.

      Consider uploading path `${presentLocally.path}` to your caches
      and adding the hash above to the list to allow users of this flake to skip fetching
      flake input `${name}` directly.

    '' false;
    knownCacheHit = (knownCachedNarHashes.${name} or {}).${hash} or warning;
  in
    # NOTE: if it's present locally, using either derivation should be
    # equivalent; nothing should build either way.
    if (globalOverride && useSubstituters) then
      knownCacheHit || presentLocally.present
    else presentLocally.present;

  facade = name: let
    lockNode = lockFile.nodes.${name};

    hash' = lockNode.locked.narHash;
    hash =
      assert (builtins.head (builtins.split "-" hash')) == "sha256"; hash';

    src = inputs.${name};

    extraAttrs = extraAttrsOnInputDrvs lockNode;

    have = checkForFixedOutputDrv { inherit name hash; };
    elided = useExistingFixedOutputDrv ({ inherit name hash; } // extraAttrs);
    fromFlakeInput = mkFixedOutputCopy ({ inherit name hash src; } // extraAttrs);
  in
    if have then elided else fromFlakeInput;
in
  builtins.mapAttrs (n: _v: facade n) inputs
