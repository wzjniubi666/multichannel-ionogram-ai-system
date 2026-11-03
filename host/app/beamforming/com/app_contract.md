# Desktop host contract

This is an independent native Tk desktop host in com/. No sealed FPGA RTL, plan,
codec, fixed reference, release gate or production host module is modified.
Target remains xc7k325tffg900-2, ACTIVE14 mask7f7f:16 input lanes,07/15 excluded,
az113/el35,512 periods, BFM1/2, PC192.0.2.2:5000 to FPGA192.0.2.1:5000.

Selection requires one complete raw M COS capture with16 distinct00..15 channels.
Quick mode uses3 frequencies ×3 lags; full mode uses the entire captured frequency
grid and118 lags. New preparation uses the sealed planner/quality gate. Cache
reuse verifies original source hashes, plan contents and the release gate.

Start is an explicit hardware action and requires administrator privileges and
the user's direct-connection/image checkbox. Offline emulator is a separate action,
uses no socket, changes no adapter and always labels results emulator. Adapter
inspection is read-only and is not labelled FPGA communication success.

Real networking reuses the existing single known Intel I219-V backup/setup/restore
functions. Backup resides in the project's existing board_20261023 recovery tree.
Every normal completion, cancellation, preparation failure, setup exception or
packet exception goes through finally restoration. Restoration failure is fatal
and surfaces the backup directory. No board programming or firewall modification.

Each frame sends1 CONFIG+32IQ and accepts1ACK+32IQ_ACK+16RESULT. Bytes displayed
are UDP application bytes, not Ethernet wire throughput. A frame is counted only
after exact response/sequence/fixed-model comparison and SQLite commit. No automatic
retry. Resume requires an explicit matching partial result/plan/source mode.

Stop cooperates: preparation stops after a frequency, transmission after the current
frame (socket timeout3s), then commits/aggregates verified frames and restores the
adapter. Window close waits for cleanup. GUI disappearance requests cancellation via
worker owner-PID checks. A killed network host, power loss or OS failure can still
require the saved manual restore entry; no forced process-tree termination button.

Only the Tk main thread touches widgets and figures. Workers run in isolated child
processes, report JSON events, and retain logs/outcome/request per job. Partial/missing
points remain NaN/gray. Blue jet0..40dB plots preserve original data. Single00 is
from the same transmitted IQ/gain, only coherent integration, no cross-channel
combining. Individual-background comparison is explicitly structural; shared
single00 background comparison is available. Neither is calibrated SNR.
