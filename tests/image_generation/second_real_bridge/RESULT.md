# Second authorized official bridge request: rejected upstream

- Started UTC: `2026-10-16T10:57:32.330497+00:00`.
- User had enabled the model and manually restarted their existing local service. No restart or credential access was performed by the agent.
- Preflight: official mode, no inflight request, zero new process calls, unit price 60 fen, one-call session cap. The historical first reservation remained in this task receipt, without requiring another service restart.
- Model: `doubao-seedream-5-0-pro-260628`, standard, 2K, one synthetic bridge drawing reference, PNG output requested.
- Input reused from `../first_real_bridge/bridge_drawing_input.png`; SHA256 `3958f22a205450ae867c9affbd13cfedcd41d448eb1a72398786caf51373ab31`, 320 x 240. No boat, people or personal image.
- Exactly one POST to the existing loopback service; no retry or fallback. End-to-end elapsed 1.255 seconds.
- Local HTTP 502 / `upstream_outcome_unknown`; retained diagnostic: upstream HTTP **429**, code **`SetLimitExceeded`**, request ID **`02179214825345768a4d5226e4976fceebdcfa7e5c0e722f7f208`**.
- No generated image was returned or saved; output decoding and visual verification therefore could not run. This is not a successful image-generation result.
- Postflight: real_calls 1, reserved_fen 60, inflight false. Historical first unknown reservation 60 + current 60 = **120 fen conservatively reserved**. Actual platform charge remains unverified.

The [official error-code reference](https://ark.volcengine.com/region:cn-beijing/docs/error-codes), fetched read-only without credentials after this attempt, lists `SetLimitExceeded` under HTTP 429 / TooManyRequests for configured model or endpoint usage limits. Its model variant directs the account owner to Model Activation / Safe Experience Mode; its endpoint variant directs them to the endpoint usage limit. Only the diagnostic code was retained, so the exact variant and configured account value are not known. This is a configured-usage-limit rejection, rather than evidence of an image result or ordinary transient request frequency. No account limit was changed.

The upstream response proves that this request reached an official API and received a structured rejection. It does not prove successful model execution, image output, or the exact account-setting field that caused this limit. An upstream 429 is independent of the local one-call session cap, since preflight passed and the local counter advanced once.

Next action: the account owner can inspect their official console's Model Activation / Safe Experience Mode and endpoint usage-limit settings, plus request records at this UTC time using the request ID. Do not send credentials, authorization headers, or full responses. Do not automatically replay the request, clear the cap, switch models, raise account limits, or restart the user's process. After the account-side cause is resolved, a new explicit single-call authorization and safe session handoff are needed for another live attempt.

The first request's underlying cause remains unknown; this second response must not be retroactively assigned to the first failure. Raw response bodies, image base64, service tokens, headers, and credentials are absent from this evidence.
