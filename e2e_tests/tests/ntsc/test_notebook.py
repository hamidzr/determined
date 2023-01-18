import re
from typing import List

import pytest

from tests import ntsc as cmd
from tests.cluster.test_workspace_org import setup_workspace
from tests.api_utils import determined_test_session
from tests.cluster.test_users import ADMIN_CREDENTIALS


@pytest.mark.slow
@pytest.mark.e2e_cpu
def test_basic_notebook_start_and_kill() -> None:
    lines = []  # type: List[str]
    with cmd.interactive_command("notebook", "start") as notebook:
        for line in notebook.stdout:
            if re.search("Jupyter Notebook .*is running at", line) is not None:
                return
            lines.append(line)

    raise ValueError(lines)


@pytest.mark.e2e_cpu
def test_nb_list() -> None:
    admin_session = determined_test_session(ADMIN_CREDENTIALS)
    # with setup_workspace(admin_session) as workspace:
