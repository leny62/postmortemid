import hashlib
import io
import json
import zipfile

import pytest
from fastapi.testclient import TestClient

from pmid_upload.app import create_app, parse_tokens

ADMIN = {"Authorization": "Bearer admin-secret"}
ALICE = {"Authorization": "Bearer alice-secret"}
PHOTO = b"\xff\xd8 fake jpeg bytes"
PATH = "/v1/photos/PM-A01/L/muzzle/20261113_090000_000_1.jpg"


@pytest.fixture
def client(tmp_path):
    app = create_app(tmp_path, parse_tokens("alice:alice-secret, bob:bob-secret"), "admin-secret")
    return TestClient(app)


def put_photo(client, path=PATH, body=PHOTO, headers=ALICE, meta=None):
    return client.put(
        path,
        content=body,
        headers=headers
        | {"X-Sha256": hashlib.sha256(body).hexdigest(), "X-Meta": json.dumps(meta or {})},
    )


def test_tokens_are_parsed_per_collector():
    assert parse_tokens("alice:a1, bob:b2") == {"a1": "alice", "b2": "bob"}
    assert parse_tokens("") == {}


def test_upload_is_idempotent_and_refuses_a_different_photo(client):
    assert put_photo(client).json() == {"status": "stored"}
    assert put_photo(client).json() == {"status": "exists"}
    assert put_photo(client, body=b"other").status_code == 409


def test_upload_checks_token_checksum_and_path(client):
    assert put_photo(client, headers={}).status_code == 401
    assert put_photo(client, headers={"Authorization": "Bearer nope"}).status_code == 401
    bad_sum = client.put(PATH, content=PHOTO, headers=ALICE | {"X-Sha256": "0" * 64})
    assert bad_sum.status_code == 400
    assert put_photo(client, path="/v1/photos/PM-A01/L/ear/x.jpg").status_code == 422
    assert put_photo(client, path="/v1/photos/cow1/L/muzzle/x.jpg").status_code == 422
    assert put_photo(client, path="/v1/photos/PM-A01/L/muzzle/x.png").status_code == 422


def test_admin_export_matches_the_app_zip_layout(client):
    put_photo(client, meta={"captured_at": "2026-11-13T09:00:00", "device_model": "Tecno"})
    put_photo(client, path="/v1/photos/PM-A01/P0/face/20261113_100000_000_2.jpg", body=b"p0")
    log = {
        "linkage_status": "confirmed",
        "slaughter_time": "2026-11-13T09:40:00",
        "head_washed": "no",
        "device_model": "Tecno",
    }
    assert client.put("/v1/animals/PM-A01", json=log, headers=ALICE).status_code == 200

    assert client.get("/v1/summary", headers=ALICE).status_code == 401
    assert client.get("/v1/summary", headers=ADMIN).json() == {
        "PM-A01": {"L/muzzle": 1, "P0/face": 1}
    }
    z = zipfile.ZipFile(io.BytesIO(client.get("/v1/export.zip", headers=ADMIN).content))
    assert sorted(z.namelist()) == [
        "PM-A01/L/muzzle/20261113_090000_000_1.jpg",
        "PM-A01/P0/face/20261113_100000_000_2.jpg",
        "field_animals.csv",
        "field_images.csv",
        "slaughter_times.csv",
    ]
    assert z.read("slaughter_times.csv").decode() == (
        "identity,slaughter_time\nPM-A01,2026-11-13T09:40:00\n"
    )
    images = z.read("field_images.csv").decode().splitlines()
    assert len(images) == 3
    assert "Tecno,alice" in images[1]
