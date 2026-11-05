mock_resource "random_password" {
  defaults = { result = "Mock-Passw0rd-For-Tests!" }
}

mock_resource "random_id" {
  defaults = { hex = "a1b2c3" }
}
