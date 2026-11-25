"""HTTP Basic roles for the teaching API. Set secrets outside the repository."""

import os
from secrets import compare_digest
from typing import Annotated

from fastapi import Depends, HTTPException
from fastapi.security import HTTPBasic, HTTPBasicCredentials

basic_auth = HTTPBasic(auto_error=False)
Credentials = Annotated[HTTPBasicCredentials | None, Depends(basic_auth)]
PASSWORD_VARIABLES = {
    "reader": "WAREHOUSE_READER_PASSWORD",
    "admin": "WAREHOUSE_ADMIN_PASSWORD",
}


def get_role(credentials: Credentials) -> str:
    if credentials is not None:
        variable = PASSWORD_VARIABLES.get(credentials.username)
        password = os.getenv(variable, "") if variable else ""
        if len(password.strip()) >= 12 and compare_digest(
            credentials.password.encode(), password.encode()
        ):
            return credentials.username
    raise HTTPException(
        status_code=401,
        detail="Authentication required",
        headers={"WWW-Authenticate": "Basic"},
    )


def require_admin(credentials: Credentials) -> None:
    if get_role(credentials) != "admin":
        raise HTTPException(status_code=403, detail="Administrator access required")


def require_item_writer(credentials: Credentials) -> None:
    # Preserve the local CRUD exercises until a role is explicitly configured.
    if any(variable in os.environ for variable in PASSWORD_VARIABLES.values()):
        require_admin(credentials)
