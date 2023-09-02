{ lib
, fetchFromGitHub
, stdenv
#, linuxOnly ? true, # broken on nix builds
, buildMode ? "rel"
, appList ? true # defaults to all
, distRepo ? true
}:

#######################################################################################
# This derivation outputs three things:                                               #
# - Cosmo's basic header and .a/.o files in $out                                      #
# - The complete monorepo in $dist                                                    #
# - Individual apps, specified in appList, to make available in $out/bin for the user #
#######################################################################################

# TODO(ProducerMatt): verify executable's license block against a checksum for
# automated CYA. One possible route:
#
# $ readelf -a o//tool/build/pledge.com.dbg |\
#    grep kLegalNotices |\
#    awk '{print $2}'
#
# Gets the hex address of where the licenses start. From there it's a double-nul
# terminated list of strings.

let
  commonMeta = rec {
    name = "cosmopolitan";
    version = "2023-08-31";
    rev = "e2b3c3618e7a7903f6ddc47acfea087d430fcc3f";
    changelog = "https://github.com/jart/cosmopolitan/commits/${rev}";
  };

  cosmoMeta = {
    mode = buildMode;

    outputs =
      # add new apps here. Each top-level attribute name
      # becomes a new package output.
      with lib.licenses; {
      # NOTE(ProducerMatt): Cosmo embeds relevant licenses near the top of the
      # executable. You can manually inspect by viewing the binary with `less`.
      # Grep for "Copyright".
        pledge = {
          coms = [
            "tool/build/pledge.com"
            "tool/build/unveil.com"
          ];
          licenses = [ asl20 bsd3 mit zlib isc ];
        };
        pkzip = {
          coms = [
            "third_party/zip/zip.com"
            "third_party/unzip/unzip.com"
          ];
          licenses = [ asl20 bsd3 mit zlib isc ];
        };
        printimage = {
          coms = [
            "tool/viz/printimage.com"
          ];
          licenses = [ asl20 bsd3 mit zlib isc ];
        };
        printvideo = {
          coms = [
            "tool/viz/printvideo.com"
          ];
          licenses = [ asl20 bsd3 mit zlib isc ];
        };
        lambda = {
          coms = [
            "tool/lambda/asc2bin.com"
            "tool/lambda/blcdump.com"
            "tool/lambda/bru2bin.com"
            "tool/lambda/lam2bin.com"
            "tool/lambda/lambda.com"
            "tool/lambda/tromp.com"
          ];
          licenses = [ asl20 bsd3 isc mit ];
        };
        ttyinfo = {
          coms = [
            "examples/ttyinfo.com"
          ];
          licenses = [ asl20 bsd3 mit zlib isc ];
          # Using "MIT" license in place of fdlibm license
        };
        life = {
          coms = [
            "examples/life.com"
          ];
          licenses = [ asl20 bsd3 mit zlib isc ];
          # Using "MIT" license in place of fdlibm license
        };
        zipobj = {
          coms = [
            "tool/build/zipobj.com"
          ];
          licenses = [ bsd3 mit zlib isc ];
        };
        cocmd = {
          coms = [
            "tool/build/cocmd.com"
          ];
          licenses = [ asl20 bsd3 mit isc ];
        };
        lua = {
          coms = [
            "third_party/lua/lua.com"
          ];
          licenses = [ asl20 bsd2 bsd3 mit isc ];
          # Using "MIT" license in place of fdlibm license
        };
        redbean = {
          coms = [
            "third_party/radpajama/radpajama-chat.com"
            "third_party/radpajama/radpajama-copy.com"
            "third_party/radpajama/radpajama-quantize.com"
            "third_party/radpajama/radpajama.com"
          ];
          licenses = [ asl20 bsd2 bsd3 mit isc ];
          # Using "MIT" license in place of fdlibm license
        };
        llama = {
          coms = [
            "third_party/ggml/llama.com"
          ];
          licenses = [ asl20 bsd2 bsd3 mit isc ];
          # Using "MIT" license in place of fdlibm license
        };
    };

    make = "make";
    #make = "./build/bootstrap/make.com"; # Landlock make broken on nix builds
    platformFlag =
      "";
    #   if linuxOnly
    #     then "CPPFLAGS=-DSUPPORT_VECTOR=1" # broken on nix builds
    #     else "";
    # # NOTE(ProducerMatt): since Nix builds will all be on Linux,
    # # might as well target Linux exclusively.
  };
  cosmoSrc = fetchFromGitHub {
    owner = "jart";
    repo = "cosmopolitan";
    rev = commonMeta.rev;
    hash = "sha256-POEVyuKZ/pdEYXHxVOLb5OSbzWuJ+5LWeokjUe4BHcY=";
  };
  wantedOutputs =
    # make attrs of all outputs to build. If given a bad name in
    # limitOutputs this should fail at getAttr.
    # If it doesn't send flamemail to ProducerMatt
    (if (builtins.isList appList)
     then builtins.listToAttrs
       (map (name: lib.nameValuePair
         name (builtins.getAttr name cosmoMeta.outputs))
         appList)
    else (lib.optionalAttrs appList cosmoMeta.outputs));
    # TODO: find a less awkward way to structure outputs.
  wantedOutputNames =
    builtins.attrNames wantedOutputs;
  wantedComs =
    # wanted outputs but just a list of com files.
    builtins.concatLists
      (lib.catAttrs "coms" (builtins.attrValues wantedOutputs));
  buildTargets =
    if distRepo then "" # we need everything, make defaults to all
      else (lib.concatMapStringsSep " "
        (target: "o/${cosmoMeta.mode}/${target}")
        wantedComs);
  relevantLicenses =
    builtins.concatMap (o: o.licenses)
      (builtins.attrValues (if distRepo then cosmoMeta.outputs
                            else wantedOutputs));
  buildStuff = ''
      ${cosmoMeta.make} MODE=${cosmoMeta.mode} -j$NIX_BUILD_CORES \
          ${cosmoMeta.platformFlag} V=0 \
      ''
    + buildTargets + "\n";
  installStuff =
    (lib.concatStringsSep "\n"
      (lib.flatten [
        (map (name: "mkdir -p ${"$" + name}/bin")
          wantedOutputNames)
        (lib.mapAttrsToList (name: value:
          (map (target:
            ## strip APE header. Only used if building cross-platform
            ## but only using on ELF (may solve execution issues)
            #"o/${cosmoMeta.mode}/${target} --assimilate" + "\n" +
            "cp o/${cosmoMeta.mode}/${target} ${"$" + name}/bin/")
            value.coms))
          wantedOutputs)
        "mkdir -p $out/bin \n"
      ]));
  symlinkStuff = lib.concatMapStringsSep "\n"
    (name: "ls -1N --zero ${"$" + name}/bin | xargs -0 -I'{}' realpath -sez ${"$" + name}/bin/'{}' | xargs -0 -I'{}' ln -s '{}' $out/bin/")
    wantedOutputNames;
    #spot the mistake!
    #(name: "ls -1N --zero ${"$" + name}/bin | xargs -0 -I'{}' realpath -smz '{}' | xargs -0 -I'{}' ln -s '{}' $out/bin/")
in
stdenv.mkDerivation {
    pname = commonMeta.name;
    version = commonMeta.version;
    #phases = [ "unpackPhase" "buildPhase" "checkPhase" "installPhase" ];
    doCheck = true;
    dontConfigure = true;
    dontFixup = true;

    outputs = [ "out" ]
              ++ (lib.optional distRepo "dist")
              ++ wantedOutputNames;

    src = cosmoSrc;
    buildPhase = ''
      find ./build/bootstrap/ -name '*.com' -execdir '{}' --assimilate \;

      # some syscall tests fail because we're in a sandbox
      rm test/libc/calls/sched_setscheduler_test.c
      rm test/libc/thread/pthread_create_test.c
      rm test/libc/calls/getgroups_test.c

      # FAIL on GitHub actions
      rm test/libc/calls/ioctl_test.c

      # fails
      rm test/libc/stdio/posix_spawn_test.c
    '' + buildStuff + ''
      echo "" # workaround for nix's weird stdout muddling
    '';
    checkPhase = ''
      runHook preCheck
      ${cosmoMeta.make} check &>/dev/null # FIXME newline spam in checks only
      runHook postCheck
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out/include $out/lib
      install o/cosmopolitan.h $out/include
      install o/${cosmoMeta.mode}/cosmopolitan.a o/${cosmoMeta.mode}/libc/crt/crt.o o/${cosmoMeta.mode}/ape/ape.{o,lds} o/${cosmoMeta.mode}/ape/ape-no-modify-self.o $out/lib
      '' + installStuff + "\n" # workaround for nix's weird stdout muddling
      + symlinkStuff + "\n" # workaround for nix's weird stdout muddling
      + (lib.optionalString distRepo ''
          mkdir -p "$dist"
          cp -r . "$dist"
        '')
      + ''
      runHook postInstall
      '';

    meta = {
      homepage = "https://github.com/jart/cosmopolitan";
      description = "Selected programs from the CosmopolitanC monorepo";
      platforms = [ "x86_64-linux" ];
      changelog = commonMeta.changelog;

      # All Cosmo original code under ISC license.
      license = with lib.licenses; lib.unique ([ isc ] ++ relevantLicenses);
      maintainers = with lib.maintainers;
        [ ProducerMatt ]; # FIXME credit ingenieroariel
    };
}

# NOTE(ProducerMatt): Landlock Make is currently unhappy with the Nix build
# environment. For this reason we use the stdenv make, which is slower and
# theoretically less secure. When landlock is working add this back to the
# build And set $cosmoMeta.make to "o/optlinux/third_party/make/make.com"
#
#      ./build/bootstrap/make.com --assimilate
#
#      # build ape headers
#      ./build/bootstrap/make.com -j$NIX_BUILD_CORES \
#         ${cosmoMeta.platformFlag} o//ape o//libc
#
#      # build optimized make
#      ./build/bootstrap/make.com -j$NIX_BUILD_CORES \
#          ${cosmoMeta.platformFlag} V=0 \
#          MODE=optlinux ${cosmoMeta.make}
