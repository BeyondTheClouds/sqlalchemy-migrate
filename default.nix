with import <nixpkgs> {};
with import <nixpkgs/nixos> {};

let py = python27.withPackages (pkgs: with pkgs; [
  # These are for spacemacs python layer. To get spacemacs with the
  # correct PATH. run nix-shell, then launch Emacs inside this
  # nix-shell.
  virtualenv
  flake8
  psycopg2 MySQL_python
]);
in stdenv.mkDerivation {
  name = "sqlalchemy-migrate";
  buildInputs = [ py zlib libffi libressl ];
  shellHook = ''
    function setup() {
      # Address to the docker registry
      local registry=\$\{1:-"192.168.56.101:5000"}

      # Start croach
      if [[ ! $(docker inspect -f {{.State.Running}} roach1 2> /dev/null) ]]
      then
        echo "INFO: start cockroach db docker."
        docker run -d --name=croach\
                      --hostname=croach\
                      --env REGISTRY_HTTP_ADDR=$registry\
                      --publish 5432:26257 --publish 8080:8080\
                      -v "$PWD/cockroach-data/roach1:/cockroach/cockroach-data"\
                      cockroachdb/cockroach:v2.0.4 start --insecure
      fi

      # Wait 'till cockroachdb starts
      sleep 1

      # Build test_migrate database in croach
      echo "INFO: create database test_migrate."
      docker exec -ti croach ./cockroach sql --insecure\
                  --execute "CREATE DATABASE test_migrate"

      echo "INFO: connect with:"
      echo "INFO: docker exec -ti croach ./cockroach sql --insecure -d test_migrate"
    }

    function teardown() {
      echo "INFO: drop database test_migrate."
      docker exec -ti croach ./cockroach sql --insecure\
                  --execute "DROP DATABASE IF EXISTS test_migrate"

      echo "INFO: stop croach container."
      docker stop croach
      echo "INFO: delete croach container."
      docker rm croach

      sudo rm -rf cockroach-data
    }

    # SetUp the virtual environment
    if [ ! -d venv ]
    then
      virtualenv --python=python2.7 venv
      source venv/bin/activate

      # spacemacs deps
      pip install service_factory
      pip install ipython
      pip install ipdb
      pip install jedi
      pip install tox

      # project
      pip install -e .
    fi

    source venv/bin/activate

    if ${lib.boolToString config.virtualisation.docker.enable}
    then
      setup
      trap "teardown" exit # teardown on CTRL+D
      # emacs &
    else
      echo "ERROR: Docker is not enabled. Please, enable it first."
    fi
  '';
}
