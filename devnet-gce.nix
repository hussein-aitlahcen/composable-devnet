{ composable,
  polkadot,
  credentials,
  localtunnel,
}:
let
  gcefy-version = version:
    builtins.replaceStrings [ "." ] [ "-" ] version;
  machine-name = "devnet-${composable.name}-${gcefy-version composable.version}-${composable.spec}";
in {
  resources.gceNetworks.composable-devnet = credentials // {
    name = "composable-devnet-network";
    firewall = {
      allow-http = {
        targetTags = [ "http" ];
        allowed.tcp = [ 80 ];
      };
      allow-https = {
        targetTags = [ "https" ];
        allowed.tcp =  [ 443 ];
      };
    };
  };
  "${machine-name}" = { pkgs, resources, ... }:
    let
      devnet = pkgs.callPackage ./devnet.nix {
        inherit composable;
        inherit polkadot;
      };
      subdomain = machine-name;
    in {
      deployment = {
        targetEnv = "gce";
        gce = credentials // {
          machineName = machine-name;
          network = resources.gceNetworks.composable-devnet;
          region = "europe-central2-c";
          instanceType = "n1-standard-16";
          rootDiskSize = 50;
          tags = [
            "http"
            "https"
          ];
        };
      };
      networking.firewall.allowedTCPPorts = [ 80 443 ];
      systemd.services.composable-devnet = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        description = "Composable Devnet";
        serviceConfig = {
          Type = "simple";
          User = "root";
          ExecStart = "${devnet}/bin/launch-devnet";
        };
      };
      systemd.services.localtunnel = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        description = "Local Tunnel Server";
        serviceConfig = {
          Type = "simple";
          User = "root";
          ExecStart = "${localtunnel}/bin/lt --port 80 --subdomain ${subdomain}";
        };
      };
      services.nginx = {
        enable = true;
        virtualHosts."${subdomain}.loca.lt" =
          let
            routify-nodes = prefix:
              map (node: (node // {
                name = prefix + node.name;
              }));
            routified-composable-nodes =
              routify-nodes "parachain/" composable.nodes;
            routified-polkadot-nodes =
              routify-nodes "relaychain/" polkadot.nodes;
            routified-nodes =
              routified-composable-nodes ++ routified-polkadot-nodes;
          in
            {
              locations = builtins.foldl' (x: y: x // y) {} (map (node: {
                "/${node.name}" = {
                  proxyPass = "http://127.0.0.1:${builtins.toString node.wsPort}";
                  proxyWebsockets = true;
                };
              }) routified-nodes);
            };
      };
    };
}
