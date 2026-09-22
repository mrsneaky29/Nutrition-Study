# Local sync service

`local_sync_server.dart` is a disposable LAN-only bridge for the prototype. It
uses only `dart:io` and writes its entire state to `.local_data/records.json`.
It is intentionally separate from the Flutter app and Firebase backend.

Set a private `LOCAL_SYNC_KEY` of at least 16 characters, then run it with
`dart run tool/local_sync_server.dart`. It binds to `0.0.0.0:8787`
by default; use `--host=...`, `--port=...`, `LOCAL_SYNC_HOST`, or
`LOCAL_SYNC_PORT` to override that. Browser clients are permitted by CORS. The
service exposes `GET /health`, `GET /records`, `POST /records`,
`PUT /records/:id`, and `POST /records/:id/archive`; it deliberately never
exposes `DELETE`.

Build both clients with the same value using
`--dart-define=LOCAL_API_KEY=<private-key>`. Requests without the matching key
are rejected. This key is only a local-development safeguard; it is not a
replacement for Firebase Authentication in production.

To remove it later, stop the server and delete these disposable files:

- `tool/local_sync_server.dart`
- `tool/LOCAL_SYNC.md`
- `lib/local_sync/`
- `lib/admin/local_api_visit_repository.dart`
- `.local_data/records.json` and an optional `records.json.bak`

Then select the Firebase implementations in `lib/main.dart` and
`lib/admin_main.dart`, remove the debug-only cleartext HTTP override, and remove
the `http` dependency if the Firebase adapters do not use it. The collector and
admin screens remain unchanged because they depend on injected boundaries.

Before removal, migrate the JSON list to the production persistence layer. Each
record uses the canonical contract:

```text
id, participant { studyId, name, indianPhone }, visitNumber, collectorId,
createdAt, updatedAt, status, syncState, reviewState, revision,
confirmation?, stepTwoMeasurement?, submittedAt?, archivedAt?, archivedBy?
```

The production replacement must keep immutable `id`, `collectorId`,
`participant.studyId`, and `createdAt`; advance `revision` and `updatedAt` on
every update; use an archive/restore operation instead of deletion; and retain
the same `GET /health`, `GET /records`, collector upsert, admin replace, and
archive semantics if existing LAN clients still need them during migration.
