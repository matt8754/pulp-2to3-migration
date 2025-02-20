#!/usr/bin/env bash
# coding=utf-8

# WARNING: DO NOT EDIT!
#
# This file was generated by plugin_template, and is managed by it. Please use
# './plugin-template --github pulp_2to3_migration' to update this file.
#
# For more info visit https://github.com/pulp/plugin_template

# make sure this script runs at the repo root
cd "$(dirname "$(realpath -e "$0")")"/../../..
REPO_ROOT="$PWD"

set -mveuo pipefail

source .github/workflows/scripts/utils.sh

export POST_SCRIPT=$PWD/.github/workflows/scripts/post_script.sh
export POST_DOCS_TEST=$PWD/.github/workflows/scripts/post_docs_test.sh
export FUNC_TEST_SCRIPT=$PWD/.github/workflows/scripts/func_test_script.sh

# Needed for both starting the service and building the docs.
# Gets set in .github/settings.yml, but doesn't seem to inherited by
# this script.
export DJANGO_SETTINGS_MODULE=pulpcore.app.settings
export PULP_SETTINGS=$PWD/.ci/ansible/settings/settings.py

export PULP_URL="https://pulp"

if [[ "$TEST" = "docs" ]]; then
  cd docs
  make PULP_URL="$PULP_URL" diagrams html
  tar -cvf docs.tar ./_build
  cd ..

  echo "Validating OpenAPI schema..."
  cat $PWD/.ci/scripts/schema.py | cmd_stdin_prefix bash -c "cat > /tmp/schema.py"
  cmd_prefix bash -c "python3 /tmp/schema.py"
  cmd_prefix bash -c "pulpcore-manager spectacular --file pulp_schema.yml --validate"

  if [ -f $POST_DOCS_TEST ]; then
    source $POST_DOCS_TEST
  fi
  exit
fi

if [[ "${RELEASE_WORKFLOW:-false}" == "true" ]]; then
  REPORTED_VERSION=$(http $PULP_URL/pulp/api/v3/status/ | jq --arg plugin pulp_2to3_migration --arg legacy_plugin pulp_2to3_migration -r '.versions[] | select(.component == $plugin or .component == $legacy_plugin) | .version')
  response=$(curl --write-out %{http_code} --silent --output /dev/null https://pypi.org/project/pulp-2to3-migration/$REPORTED_VERSION/)
  if [ "$response" == "200" ];
  then
    echo "pulp-2to3-migration $REPORTED_VERSION has already been released. Skipping running tests."
    exit
  fi
fi

if [[ "$TEST" == "plugin-from-pypi" ]]; then
  COMPONENT_VERSION=$(http https://pypi.org/pypi/pulp-2to3-migration/json | jq -r '.info.version')
  git checkout ${COMPONENT_VERSION} -- pulp-2to3-migration/tests/
fi

cd ../pulp-openapi-generator
./generate.sh pulpcore python
pip install ./pulpcore-client
rm -rf ./pulpcore-client
if [[ "$TEST" = 'bindings' ]]; then
  ./generate.sh pulpcore ruby 0
  cd pulpcore-client
  gem build pulpcore_client.gemspec
  gem install --both ./pulpcore_client-0.gem
fi
./generate.sh pulp_file python
pip install ./pulp_file-client
rm -rf ./pulp_file-client
if [[ "$TEST" = 'bindings' ]]; then
  ./generate.sh pulp_file ruby 0
  cd pulp_file-client
  gem build pulp_file_client.gemspec
  gem install --both ./pulp_file_client-0.gem
  cd ..
fi
./generate.sh pulp_container python
pip install ./pulp_container-client
rm -rf ./pulp_container-client
if [[ "$TEST" = 'bindings' ]]; then
  ./generate.sh pulp_container ruby 0
  cd pulp_container-client
  gem build pulp_container_client.gemspec
  gem install --both ./pulp_container_client-0.gem
  cd ..
fi
./generate.sh pulp_rpm python
pip install ./pulp_rpm-client
rm -rf ./pulp_rpm-client
if [[ "$TEST" = 'bindings' ]]; then
  ./generate.sh pulp_rpm ruby 0
  cd pulp_rpm-client
  gem build pulp_rpm_client.gemspec
  gem install --both ./pulp_rpm_client-0.gem
  cd ..
fi
./generate.sh pulp_deb python
pip install ./pulp_deb-client
rm -rf ./pulp_deb-client
if [[ "$TEST" = 'bindings' ]]; then
  ./generate.sh pulp_deb ruby 0
  cd pulp_deb-client
  gem build pulp_deb_client.gemspec
  gem install --both ./pulp_deb_client-0.gem
  cd ..
fi
cd $REPO_ROOT

if [[ "$TEST" = 'bindings' ]]; then
  if [ -f $REPO_ROOT/.ci/assets/bindings/test_bindings.py ]; then
    python $REPO_ROOT/.ci/assets/bindings/test_bindings.py
  fi
  if [ -f $REPO_ROOT/.ci/assets/bindings/test_bindings.rb ]; then
    ruby $REPO_ROOT/.ci/assets/bindings/test_bindings.rb
  fi
  exit
fi

cat unittest_requirements.txt | cmd_stdin_prefix bash -c "cat > /tmp/unittest_requirements.txt"
cmd_prefix pip3 install -r /tmp/unittest_requirements.txt

# check for any uncommitted migrations
echo "Checking for uncommitted migrations..."
cmd_prefix bash -c "django-admin makemigrations --check --dry-run"

if [[ "$TEST" != "upgrade" ]]; then
  # Run unit tests.
  cmd_prefix bash -c "PULP_DATABASES__default__USER=postgres django-admin test --noinput /usr/local/lib/python3.8/site-packages/pulp_2to3_migration/tests/unit/"
fi

# Run functional tests
export PYTHONPATH=$REPO_ROOT/../pulp_file${PYTHONPATH:+:${PYTHONPATH}}
export PYTHONPATH=$REPO_ROOT/../pulp_container${PYTHONPATH:+:${PYTHONPATH}}
export PYTHONPATH=$REPO_ROOT/../pulp_rpm${PYTHONPATH:+:${PYTHONPATH}}
export PYTHONPATH=$REPO_ROOT/../pulp_deb${PYTHONPATH:+:${PYTHONPATH}}
export PYTHONPATH=$REPO_ROOT/../pulpcore${PYTHONPATH:+:${PYTHONPATH}}
export PYTHONPATH=$REPO_ROOT${PYTHONPATH:+:${PYTHONPATH}}



if [[ "$TEST" == "performance" ]]; then
  if [[ -z ${PERFORMANCE_TEST+x} ]]; then
    pytest -vv -r sx --color=yes --pyargs --capture=no --durations=0 pulp_2to3_migration.tests.performance
  else
    pytest -vv -r sx --color=yes --pyargs --capture=no --durations=0 pulp_2to3_migration.tests.performance.test_$PERFORMANCE_TEST
  fi
  exit
fi

if [ -f $FUNC_TEST_SCRIPT ]; then
  source $FUNC_TEST_SCRIPT
else
    pytest -v -r sx --color=yes --pyargs pulp_2to3_migration.tests.functional
fi
pushd ../pulp-cli
pytest -v -m pulp_2to3_migration
popd

if [ -f $POST_SCRIPT ]; then
  source $POST_SCRIPT
fi
