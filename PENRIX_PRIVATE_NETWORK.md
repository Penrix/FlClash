# Penrix Private Network

This branch adds a private routing layer above subscription configuration without replacing upstream proxy/profile parsing.

Current first-stage goals:

- keep ChatGPT routing deterministic in rule mode;
- apply selected service routing by process/domain;
- keep UAA on direct routing;
- inject a Mihomo MRS ad/tracker rule provider;
- preserve the private layer across standard, script, and custom profile overwrite modes;
- expose persistent per-service toggles through the FlClash UI.

Real-device acceptance remains authoritative. A successful CI build is only an engineering gate, not proof that a site or app works correctly on-device.
