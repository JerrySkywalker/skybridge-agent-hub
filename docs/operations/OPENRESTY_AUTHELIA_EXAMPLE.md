# OpenResty And Authelia Example

This is a placeholder-only example. Do not copy production secrets into this repository.

```nginx
server {
  listen 443 ssl;
  server_name skybridge.example.com;

  # ssl_certificate /path/outside/repo/fullchain.pem;
  # ssl_certificate_key /path/outside/repo/privkey.pem;

  location / {
    # Authelia auth_request placeholder.
    # auth_request /authelia;
    proxy_pass http://127.0.0.1:8787;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
}
```

Real OpenResty, Authelia and 1Panel changes are outside the autonomous default workflow.
