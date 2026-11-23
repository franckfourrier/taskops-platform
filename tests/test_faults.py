def test_sans_fault_rate_aucune_panne(client):
    assert client.get("/tasks").status_code == 200


def test_fault_rate_1_toutes_les_requetes_metier_echouent(client, monkeypatch):
    monkeypatch.setenv("FAULT_RATE", "1")
    response = client.get("/tasks")
    assert response.status_code == 500
    assert "panne injectée" in response.json()["detail"]
    # les sondes et le scraping ne sont jamais touchés
    assert client.get("/health").status_code == 200
    assert client.get("/metrics").status_code == 200
    # la panne est bien comptée dans les métriques (visible par Prometheus)
    assert 'status="500"' in client.get("/metrics").text


def test_fault_rate_invalide_ignore(client, monkeypatch):
    monkeypatch.setenv("FAULT_RATE", "abc")
    assert client.get("/tasks").status_code == 200
