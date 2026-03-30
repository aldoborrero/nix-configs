{ lib, ... }:
let
  nxbCommon = {
    user = "root";
    port = 2222;
    serverAliveInterval = 60;
    extraOptions = {
      PubkeyAcceptedKeyTypes = "ssh-ed25519";
      IPQoS = "throughput";
    };
  };

  mkNxb = name: hostname: {
    ${name} = nxbCommon // { inherit hostname; };
  };
in
{
  programs.ssh = {
    enable = true;
    matchBlocks = lib.mkMerge [
      # Dev — HA (routes to nearest available region)
      (mkNxb "nxb-dev" "fd7a:115c:a1e0:b1a:0:cc:fefe:0004")
      (mkNxb "nxb-dev-us-east-2" "fd7a:115c:a1e0:b1a:0:cc:fefe:000a")
      (mkNxb "nxb-dev-us-west-2" "fd7a:115c:a1e0:b1a:0:cc:fefe:004a")

      # Prod — HA (routes to nearest available region)
      (mkNxb "nxb-prod" "fd7a:115c:a1e0:b1a:0:cd:fefe:0004")
      (mkNxb "nxb-prod-us-east-2" "fd7a:115c:a1e0:b1a:0:cd:fefe:000a")
      (mkNxb "nxb-prod-us-west-2" "fd7a:115c:a1e0:b1a:0:cd:fefe:004a")
    ];
  };
}
