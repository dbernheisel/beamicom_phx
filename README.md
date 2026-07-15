# BeamicomPhx

Web client for the [`beamicom`](https://github.com/dbernheisel/beamicom) NES
emulator: a Phoenix app that streams a running console's audio/video to the
browser and relays controller input back. It's the server/client counterpart
to the desktop
[`beamicom_scenic`](https://github.com/dbernheisel/beamicom_scenic) window —
same core, different sink.

> **Status:** scaffold. This is currently a fresh `phx.new` app; the
> `beamicom` sink (subscribing to `Beamicom.NES.Output` and pushing frames over
> a LiveView/channel) is not wired up yet.

## Setup

Depends on `beamicom` as a sibling path dependency, so clone both next to each
other:

```
~/beamicom          # the core emulator
~/beamicom_phx      # this project
```

Then:

* `mix setup` — install deps and build assets
* `mix phx.server` (or `iex -S mix phx.server`) — start the endpoint

Visit [`localhost:4000`](http://localhost:4000).

## Learn more

* Phoenix guides: https://phoenix.hexdocs.pm/overview.html
* Deployment: https://phoenix.hexdocs.pm/deployment.html
