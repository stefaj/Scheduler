with import <nixpkgs> { };

haskell.lib.buildStackProject {
    name = "Scheduler";
    ghc = haskell.packages.ghc801.ghc;
    buildInputs = [ ncurses 
                    stack
                    git
                    cabal-install  ]; 

    shellHook = ''
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    '';

}

