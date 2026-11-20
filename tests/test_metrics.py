def test_metrics_exposes_red_metrics(client):
    client.post("/tasks", json={"title": "mesurer"})
    client.get("/tasks")

    response = client.get("/metrics")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")

    body = response.text
    assert 'taskops_http_requests_total{method="POST",route="/tasks",status="201"}' in body
    bucket = 'taskops_http_request_duration_seconds_bucket{le="0.005",method="GET",route="/tasks"}'
    assert bucket in body
    assert "taskops_tasks_created_total" in body


def test_metrics_ignores_probes_and_scraping(client):
    client.get("/health")
    body = client.get("/metrics").text
    assert 'route="/health"' not in body
    assert 'route="/metrics"' not in body
