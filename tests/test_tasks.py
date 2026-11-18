def test_list_tasks_empty(client):
    response = client.get("/tasks")
    assert response.status_code == 200
    assert response.json() == []


def test_create_then_list_task(client):
    created = client.post("/tasks", json={"title": "Écrire le pipeline CI"})
    assert created.status_code == 201
    body = created.json()
    assert body["id"] >= 1
    assert body["title"] == "Écrire le pipeline CI"
    assert body["done"] is False

    listed = client.get("/tasks").json()
    assert [t["title"] for t in listed] == ["Écrire le pipeline CI"]


def test_create_task_rejects_empty_title(client):
    response = client.post("/tasks", json={"title": ""})
    assert response.status_code == 422
