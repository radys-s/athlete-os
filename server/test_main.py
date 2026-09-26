from fastapi.testclient import TestClient

from main import CATALOG_IDS, app, valid_candidates


def test_only_known_unique_candidates_are_returned():
    known = next(iter(CATALOG_IDS))
    assert valid_candidates('{"exercise_ids": ["wrong", "' + known + '", "' + known + '"]}') == [known]


def test_uncertain_or_malformed_response_is_empty():
    assert valid_candidates('{"exercise_ids": []}') == []
    assert valid_candidates('unknown machine') == []


def test_scan_requires_authentication_before_using_provider():
    response = TestClient(app).post('/v1/machine-scan',
        files={'photo': ('machine.jpg', b'\xff\xd8\xfftest', 'image/jpeg')})
    assert response.status_code == 401
