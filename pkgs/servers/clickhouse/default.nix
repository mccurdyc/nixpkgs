{ lib
, llvmPackages
, fetchFromGitHub
, cmake
, ninja
, python3
, perl
, yasm
, nixosTests
, darwin
, findutils

# currently for BLAKE3 hash function
, rustSupport ? true

, corrosion
, rustc
, cargo
, rustPlatform
}:

let
  inherit (llvmPackages) stdenv;
  mkDerivation = (
    if stdenv.isDarwin
    then darwin.apple_sdk_11_0.llvmPackages_15.stdenv
    else llvmPackages.stdenv).mkDerivation;
in mkDerivation rec {
  pname = "clickhouse";
  version = "23.3.3.52";

  src = fetchFromGitHub rec {
    owner = "ClickHouse";
    repo = "ClickHouse";
    rev = "v${version}-lts";
    fetchSubmodules = true;
    hash = "sha256-fVwwMj0WbyCbe4WfpYMGVM6vXFgHsjg9MUZbNyd+a/w=";
    postFetch = ''
      # delete files that make the source too big
      rm -rf $out/contrib/llvm-project/llvm/test
      rm -rf $out/contrib/llvm-project/clang/test
      rm -rf $out/contrib/croaring/benchmarks

      # fix case insensitivity on macos https://github.com/NixOS/nixpkgs/issues/39308
      rm -rf $out/contrib/sysroot/linux-*
      rm -rf $out/contrib/liburing/man
    '';
  };

  strictDeps = true;
  nativeBuildInputs = [
    cmake
    ninja
    python3
    perl
  ] ++ lib.optionals stdenv.isx86_64 [
    yasm
  ] ++ lib.optionals stdenv.isDarwin [
    llvmPackages.bintools
    findutils
    darwin.bootstrap_cmds
  ] ++ lib.optionals rustSupport [
    rustc
    cargo
    rustPlatform.cargoSetupHook
  ];

  corrosionDeps = if rustSupport then corrosion.cargoDeps else null;
  blake3Deps = if rustSupport then rustPlatform.fetchCargoTarball {
    inherit src;
    name = "blake3-deps";
    preBuild = "cd rust/BLAKE3";
    hash = "sha256-lDMmmsyjEbTfI5NgTgT4+8QQrcUE/oUWfFgj1i19W0Q=";
  } else null;
  skimDeps = if rustSupport then rustPlatform.fetchCargoTarball {
    inherit src;
    name = "skim-deps";
    preBuild = "cd rust/skim";
    hash = "sha256-gEWB+U8QrM0yYyMXpwocszJZgOemdTlbSzKNkS0NbPk=";
  } else null;

  dontCargoSetupPostUnpack = true;
  postUnpack = lib.optionalString rustSupport ''
    pushd source

    # their vendored version is too old and missing this patch: https://github.com/corrosion-rs/corrosion/pull/205
    rm -rf contrib/corrosion
    cp -r --no-preserve=mode ${corrosion.src} contrib/corrosion

    pushd contrib/corrosion/generator
    cargoDeps="$corrosionDeps" cargoSetupPostUnpackHook
    corrosionDepsCopy="$cargoDepsCopy"
    popd

    pushd rust/BLAKE3
    cargoDeps="$blake3Deps" cargoSetupPostUnpackHook
    blake3DepsCopy="$cargoDepsCopy"
    popd

    pushd rust/skim
    cargoDeps="$skimDeps" cargoSetupPostUnpackHook
    skimDepsCopy="$cargoDepsCopy"
    popd

    popd
  '';

  postPatch = ''
    patchShebangs src/

    substituteInPlace src/Storages/System/StorageSystemLicenses.sh \
      --replace 'git rev-parse --show-toplevel' '$src'
    substituteInPlace utils/check-style/check-duplicate-includes.sh \
      --replace 'git rev-parse --show-toplevel' '$src'
    substituteInPlace utils/check-style/check-ungrouped-includes.sh \
      --replace 'git rev-parse --show-toplevel' '$src'
    substituteInPlace utils/list-licenses/list-licenses.sh \
      --replace 'git rev-parse --show-toplevel' '$src'
    substituteInPlace utils/check-style/check-style \
      --replace 'git rev-parse --show-toplevel' '$src'
  '' + lib.optionalString stdenv.isDarwin ''
    sed -i 's|gfind|find|' cmake/tools.cmake
    sed -i 's|ggrep|grep|' cmake/tools.cmake
  '' + lib.optionalString rustSupport ''

    pushd contrib/corrosion/generator
    cargoDepsCopy="$corrosionDepsCopy" cargoSetupPostPatchHook
    popd

    pushd rust/BLAKE3
    cargoDepsCopy="$blake3DepsCopy" cargoSetupPostPatchHook
    popd

    pushd rust/skim
    cargoDepsCopy="$skimDepsCopy" cargoSetupPostPatchHook
    popd

    cargoSetupPostPatchHook() { true; }
  '';

  cmakeFlags = [
    "-DENABLE_TESTS=OFF"
    "-DCOMPILER_CACHE=disabled"
    "-DENABLE_EMBEDDED_COMPILER=ON"
    "-DWERROR=OFF"
  ];

  postInstall = ''
    rm -rf $out/share/clickhouse-test

    sed -i -e '\!<log>/var/log/clickhouse-server/clickhouse-server\.log</log>!d' \
      $out/etc/clickhouse-server/config.xml
    substituteInPlace $out/etc/clickhouse-server/config.xml \
      --replace "<errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>" "<console>1</console>"
    substituteInPlace $out/etc/clickhouse-server/config.xml \
      --replace "<level>trace</level>" "<level>warning</level>"
  '';

  # Builds in 7+h with 2 cores, and ~20m with a big-parallel builder.
  requiredSystemFeatures = [ "big-parallel" ];

  passthru.tests.clickhouse = nixosTests.clickhouse;

  meta = with lib; {
    homepage = "https://clickhouse.com";
    description = "Column-oriented database management system";
    license = licenses.asl20;
    maintainers = with maintainers; [ orivej ];

    # not supposed to work on 32-bit https://github.com/ClickHouse/ClickHouse/pull/23959#issuecomment-835343685
    platforms = lib.filter (x: (lib.systems.elaborate x).is64bit) (platforms.linux ++ platforms.darwin);
    broken = stdenv.buildPlatform != stdenv.hostPlatform;
  };
}
