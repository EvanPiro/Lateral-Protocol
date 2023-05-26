{
  description = "SignDBOracle";

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-darwin";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [];

      shellHook = ''
        curl -L https://foundry.paradigm.xyz | bash
        source ~/.bashrc
        foundryup
      '';
    };

    formatter.${system} = pkgs.alejandra;
  };
}
