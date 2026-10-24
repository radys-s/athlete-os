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


class _Reply:
    def __init__(self, status_code, body):
        self.status_code = status_code
        self._body = body

    def json(self):
        return self._body


def _scan_with_vision(monkeypatch, vision):
    import httpx
    import main

    calls = []

    async def fake_authenticate(token, client):
        return "user"

    async def fake_rpc(name, token, client, body):
        calls.append((name, body))
        return _Reply(200, "2026-10-24")

    async def fake_post(self, url, **kwargs):
        return vision()

    monkeypatch.setenv("OPENAI_API_KEY", "test")
    monkeypatch.setattr(main, "authenticate", fake_authenticate)
    monkeypatch.setattr(main, "_scan_rpc", fake_rpc)
    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)
    response = TestClient(app).post('/v1/machine-scan',
        headers={'Authorization': 'Bearer token'},
        files={'photo': ('machine.jpg', b'\xff\xd8\xfftest', 'image/jpeg')})
    return response, calls


def test_failed_vision_call_releases_the_reserved_scan(monkeypatch):
    response, calls = _scan_with_vision(monkeypatch, lambda: _Reply(500, {}))
    assert response.status_code == 503
    assert calls == [("reserve_scan", {}), ("release_scan", {"p_day": "2026-10-24"})]


def test_answered_scan_is_charged(monkeypatch):
    known = next(iter(CATALOG_IDS))
    body = {"output": [{"content": [{"type": "output_text",
        "text": '{"exercise_ids": ["' + known + '"]}'}]}]}
    response, calls = _scan_with_vision(monkeypatch, lambda: _Reply(200, body))
    assert response.status_code == 200
    assert response.json() == {"exercise_ids": [known]}
    assert calls[-1] == ("commit_scan", {"p_day": "2026-10-24"})


def test_unreachable_vision_provider_releases_the_scan(monkeypatch):
    import httpx

    def boom():
        raise httpx.ConnectError("down")
    response, calls = _scan_with_vision(monkeypatch, boom)
    assert response.status_code == 503
    assert calls[-1][0] == "release_scan"


def test_image_rejected_by_provider_is_charged(monkeypatch):
    response, calls = _scan_with_vision(monkeypatch, lambda: _Reply(400, {}))
    assert response.status_code == 422
    assert calls[-1][0] == "commit_scan"


def test_unexpected_error_release_is_recorded(monkeypatch):
    import httpx
    import main

    calls = []

    async def fake_authenticate(token, client):
        return "user"

    async def fake_rpc(name, token, client, body):
        calls.append(name)
        return _Reply(200, "2026-10-24")

    async def fake_post(self, url, **kwargs):
        raise RuntimeError("bug")

    monkeypatch.setenv("OPENAI_API_KEY", "test")
    monkeypatch.setattr(main, "authenticate", fake_authenticate)
    monkeypatch.setattr(main, "_scan_rpc", fake_rpc)
    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)
    client = TestClient(app, raise_server_exceptions=False)
    response = client.post('/v1/machine-scan', headers={'Authorization': 'Bearer token'},
        files={'photo': ('machine.jpg', b'\xff\xd8\xfftest', 'image/jpeg')})
    assert response.status_code == 500
    assert calls == ["reserve_scan", "release_scan"]
