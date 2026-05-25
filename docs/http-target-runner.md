# HTTP Target Runner

`examples/http_target_runner` demonstrates the HTTP API testing path for
Gransk-facing PBT runners.

Build it:

```sh
odin build examples/http_target_runner -out:/tmp/pbt-http-target-runner
```

List properties:

```sh
/tmp/pbt-http-target-runner --list-properties
```

Run it against an endpoint that accepts JSON `POST` requests:

```sh
/tmp/pbt-http-target-runner --target http://127.0.0.1:8080/items --num-tests 100 --seed 123
```

`PBT_HTTP_BASE_URL` is also accepted for environments that prefer target
configuration through environment variables.

The property generates schema-shaped JSON with:

- `id`: UUID v4 string
- `sku`: generated string
- `owner`: generated `.test` email address
- `status`: one of `draft`, `active`, or `archived`
- `quantity`: integer from 1 through 100
- `active`: generated boolean
- `created_on`: generated `YYYY-MM-DD` date from 2020 through 2030

The request uses `http_post_json`, a 1 second timeout, and a 64 KiB response cap.
Failures include the generated request body as counterexample context plus the
HTTP/process event trace in the JSON result.

For local smoke testing, a tiny Python endpoint is enough:

```sh
python3 - <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        self.rfile.read(length)
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass

HTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
PY
```

Keep the server running in one terminal, then run the PBT runner from another.
