from locust import HttpUser, between, task


class WarehouseReader(HttpUser):
    wait_time = between(0.25, 0.75)

    @task(2)
    def catalog(self):
        self.client.get("/items")

    @task
    def search(self):
        self.client.get("/items", params={"search": "Мыш"}, name="/items?search")

    @task
    def detail(self):
        self.client.get("/items/1")
