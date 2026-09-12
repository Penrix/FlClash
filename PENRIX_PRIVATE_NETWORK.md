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

The private Android workflow formats the private Dart sources before analysis and build so APK validation is not blocked by whitespace-only drift. Its routing tests temporarily disable the unrelated setup/Rust native build hooks, then restore them before the real Android build. The upstream build workflow remains the stricter repository-wide formatting gate.

Real-device acceptance remains authoritative. A successful CI build is only an engineering gate, not proof that a site or app works correctly on-device.
