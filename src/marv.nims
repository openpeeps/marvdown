--mm:arc
--threads:on
# --define:useMalloc
# --define:toktokdebug
--define:watchoutBrowserSync
when defined release:
  # --define:danger
  --opt:speed
  --passC:"-flto"
  # --checks:off