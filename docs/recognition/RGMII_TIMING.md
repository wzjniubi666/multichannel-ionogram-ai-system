# Final gigabit RGMII implementation

Receiver/MAC clock uses a BUFR in BYPASS mode in clock region X0Y2. Five calibrated IDELAYE2 input delays use 8 taps, chosen from setup/hold margin scans. The unused optional packet trace RAM was removed (16 BRAM tiles), leaving all convolution features and UDP request/reply memories intact. One feature BRAM was relocated to release a regional slot; all other convolution placement was retained.

PHY RX/TX internal 2ns clock delays are enabled and checked via MDIO. Realtek specifies >=1.2ns integrated-delay output setup/hold. The input model includes 0.05ns board skew, transition range [-2.85,-1.15]ns for each DDR half cycle. A separate virtual launch clock scopes edge constraints to the five PHY inputs: matching-edge zero-cycle setup and next opposite-edge hold (4ns later). All internal core/MAC setup and hold checks remain active.

TX output timing budgets PHY internal delay as 2ns +/-0.5ns and setup/hold >=1ns. Data/control DRIVE=8. All final setup and hold paths must pass before bit generation; no timing-failed bit is accepted. Board skew bounds are prototype assumptions, not measured hardware certification.

This build used a documented primitive/placement ECO on routed.dcp; regional_final.tcl is retained. RTL and board.xdc contain equivalent final clock/delay/cache settings for source rebuilds. The final bit, routed checkpoint, source, model and parameter hashes are in build_evidence.json.

References: Realtek RTL8211F datasheet table 58; AMD PG160; Enclustra GigabitEthernetAppNote chapter 5.
https://docs.amd.com/r/en-US/pg160-gmii-to-rgmii/Constraining-the-Core
https://github.com/enclustra/GigabitEthernetAppNote/blob/master/Chapter-5-GMII_to_RGMII.md
