import socket
from time import sleep
import unittest
from pulpcore.client.pulpcore import (
    ApiClient as CoreApiClient,
    Configuration,
    TasksApi
)
from pulpcore.client.pulp_file import (
    ApiClient as FileApiClient,
    ContentFilesApi,
    RepositoriesFileApi,
    RepositoriesFileVersionsApi
)
from pulpcore.client.pulp_2to3_migration import (
    ApiClient as MigrationApiClient,
    MigrationPlansApi
)
from pulp_2to3_migration.pulp2.base import Repository as Pulp2Repository, RepositoryContentUnit
from pulp_2to3_migration.pulp2.connection import initialize

# Can't import ISO model due to PLUGIN_MIGRATORS needing Django app
# from pulp_2to3_migration.app.plugin.iso.pulp2_models import ISO


def monitor_task(tasks_api, task_href):
    """Polls the Task API until the task is in a completed state.

    Prints the task details and a success or failure message. Exits on failure.

    Args:
        tasks_api (pulpcore.client.pulpcore.TasksApi): an instance of a configured TasksApi client
        task_href(str): The href of the task to monitor

    Returns:
        list[str]: List of hrefs that identify resource created by the task

    """
    completed = ['completed', 'failed', 'canceled']
    task = tasks_api.read(task_href)
    while task.state not in completed:
        sleep(2)
        task = tasks_api.read(task_href)
    if task.state == 'completed':
        print("The task was successful.")
    else:
        print("The task did not finish successfully.")
    return task


class TestMigrationPlan(unittest.TestCase):
    """Test the APIs for creating a Migration Plan."""

    @classmethod
    def setUpClass(cls):
        """
        Create all the client instances needed to communicate with Pulp.
        """

        # Initialize MongoDB connection
        initialize()

        configuration = Configuration()
        configuration.username = 'admin'
        configuration.password = 'password'
        configuration.host = 'http://{}:24817'.format(socket.gethostname())
        configuration.safe_chars_for_path_param = '/'

        core_client = CoreApiClient(configuration)
        file_client = FileApiClient(configuration)
        migration_client = MigrationApiClient(configuration)

        # Create api clients for all resource types
        cls.file_repo_api = RepositoriesFileApi(file_client)
        cls.file_repo_versions_api = RepositoriesFileVersionsApi(file_client)
        cls.file_content_api = ContentFilesApi(file_client)
        cls.tasks_api = TasksApi(core_client)
        cls.migration_plans_api = MigrationPlansApi(migration_client)

    def test_migrate_iso_repositories(self):
        """Test that a Migration Plan to migrate ISO content executes correctly."""
        migration_plan = '{"plugins": [{"type": "iso"}]}'
        mp = self.migration_plans_api.create({'plan': migration_plan})
        mp_run_response = self.migration_plans_api.run(mp.pulp_href, data={})
        task = monitor_task(self.tasks_api, mp_run_response.task)
        self.assertEqual(task.state, "completed")
        pulp2repositories = Pulp2Repository.objects.all()
        for pulp2repo in pulp2repositories:
            pulp3repos = self.file_repo_api.list(name=pulp2repo.repo_id)
            repo_href = pulp3repos.results[0].pulp_href
            self.failIf(not pulp3repos.results,
                        "Missing a Pulp 3 repository for Pulp 2 "
                        "repository id '{}'".format(pulp2repo.repo_id))
            # Assert that the name in pulp 3 matches the repo_id in pulp 2
            self.assertEqual(pulp2repo.repo_id, pulp3repos.results[0].name)
            # Assert that there is a Repository Version with the same number of content units as
            # associated with the repository in Pulp 2.
            repo_version_href = self.file_repo_versions_api.list(repo_href).results[0].pulp_href
            pulp2_repo_content = RepositoryContentUnit.objects.filter(repo_id=pulp2repo.repo_id)
            repo_version_content = self.file_content_api.list(repository_version=repo_version_href)
            self.assertEqual(pulp2_repo_content.count(), repo_version_content.count)
