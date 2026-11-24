# Integration notes
Historical integration notes were superseded by README.md and the report. Authoritative status:
- Vivado synthesis, implementation and timing were run on the final design (50 MHz); results in `reports/timing_final.txt`, `util_final.txt`, `power_final.txt`.
- The design was run on the Zybo Z7-10; ILA captures are in `hw_captures/`.
- The CTL proof of arbiter starvation freedom was done in NuSMV (`formal/`, `reports/ctl_formal_verification_report.md`).
- The codec design-space study is in `codec_study/`.
- `fw_board_demo` is endless by design, so it does not produce a PASS line under `tb_soc_log`; the system test uses `fw_ecc_log`.
