# Public-source publication

This repository preserves the requested docs / fpga / host / metrics / skill / report hierarchy and the two subsystem namespaces. It includes project source, upstream notices, the supplied best.pt, matching MEM files and build scripts, numerical fixtures and selected figures.

Manufacturer PDFs/spreadsheets, generated DCPs, private execution logs, adapter/session backups, historical release seals, local provenance paths and duplicate migration history are not published. Source examples and metadata are anonymized; numerical model arrays, model weights are preserved; original bit/LTX files are omitted because they may embed the original network configuration.

The public sample plan is a software-verification fixture. Production board operation needs an explicitly configured local workspace and a freshly verified release binding; do not bypass the original release gate. Board-tutorial RTL retains its original provenance and is not silently relicensed under the project's AGPL licence.

YOLO is run on the separate computer with its existing Python/PyTorch environment. This publication does not claim a newly executed full-model or hardware run.

Network endpoints in source and documentation have been replaced with documentation-only placeholders. Original bitstreams/LTX are not published. Configure local addresses and rebuild before hardware use; see docs/network_configuration.md. Tool installation examples are retained with the owner's permission.

Eight Ethernet simulation fixtures have anonymized IP/MAC headers and regenerated IPv4/UDP checksums and Ethernet FCS. One model pickle metadata path is anonymized without changing any tensor archive member.
