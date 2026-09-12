# Penrix Private Network

This branch adds a private routing layer above subscription configuration without replacing upstream proxy/profile parsing.

Current first-stage goals:

- keep ChatGPT routing deterministic in rule mode;
- apply selected service routing by process/domain;
- keep UAA on direct routing;
- inject a Mihomo MRS ad/tracker rule provider;
- preserve the private layer across standard, script, and custom profile overwrite modes;
- expose persistent per-service toggles through the FlClash UI;
- build an arm64 debug APK through the dedicated private Android CI workflow.

Self-review invariants:

- private P0 rules stay ahead of subscription and standard/custom overwrite rules;
- ChatGPT target inference never borrows a target merely because another enhanced service uses it;
- rule-provider downloads avoid `url-test` groups because current Mihomo versions have a known provider-download edge case there;
- process matching is forced only while at least one process-based app enhancement is enabled;
- failed private-setting applications roll back to the previous persisted setting and reapply it;
- the debug Android package uses the upstream `.dev` application-id suffix so it can coexist with the official package.

The private Android workflow treats committed formatting as part of reproducibility. It runs the formatter, prints any diff, and fails if the working tree changes. Routing tests temporarily disable the unrelated setup/Rust native build hooks, then restore them before the real Android build.

Real-device acceptance remains authoritative. A successful CI build is only an engineering gate, not proof that a site or app works correctly on-device.
